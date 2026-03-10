function Get-SoftwareCenterDeployments {
    <#
    .SYNOPSIS
        Queries SCCM/MECM client for available Software Center deployments.

    .DESCRIPTION
        Queries the WMI namespace root\ccm\ClientSDK for CCM_Application and
        CCM_Program instances, combines them into a unified list, and filters
        out deployments that are already installed (auto-suppress).

        Intended to be dot-sourced into Invoke-ToastFromSoftwareCenter.ps1.

    .OUTPUTS
        System.Collections.Generic.List[PSCustomObject]
        Each object has: Name, Description, IsInstalled, Type.
        Returns $null when the SCCM client namespace is unavailable.

    .NOTES
        Uses Get-CimInstance (codebase convention — not Get-WmiObject).
    #>
    param()

    $Namespace = 'root\ccm\ClientSDK'

    # ------------------------------------------------------------------
    # 1. Verify that the SCCM client WMI namespace is reachable
    # ------------------------------------------------------------------
    try {
        $null = Get-CimInstance -Namespace $Namespace -ClassName 'CCM_Application' -ErrorAction Stop
    }
    catch {
        Write-Log -Level Warn -Message "SCCM client WMI namespace '$Namespace' is not available. Error: $($_.Exception.Message)"
        return $null
    }

    # ------------------------------------------------------------------
    # 2. Query CCM_Application (Applications)
    # ------------------------------------------------------------------
    $applications = [System.Collections.Generic.List[PSCustomObject]]::new()
    try {
        $appResults = Get-CimInstance -Namespace $Namespace -ClassName 'CCM_Application' -ErrorAction Stop |
            Select-Object Name, Description, InstallState

        if ($appResults) {
            foreach ($app in @($appResults)) {
                $applications.Add([PSCustomObject]@{
                    Name        = $app.Name
                    Description = $app.Description
                    IsInstalled = ($app.InstallState -eq 'Installed')
                    Type        = 'Application'
                })
            }
        }
    }
    catch {
        Write-Log -Level Warn -Message "Failed to query CCM_Application: $($_.Exception.Message)"
    }

    # ------------------------------------------------------------------
    # 3. Query CCM_Program (Packages / Programs)
    # ------------------------------------------------------------------
    $programs = [System.Collections.Generic.List[PSCustomObject]]::new()
    try {
        $pgmResults = Get-CimInstance -Namespace $Namespace -ClassName 'CCM_Program' -ErrorAction Stop |
            Select-Object Name, Description, ResolvedState

        if ($pgmResults) {
            foreach ($pgm in @($pgmResults)) {
                $programs.Add([PSCustomObject]@{
                    Name        = $pgm.Name
                    Description = $pgm.Description
                    IsInstalled = ($pgm.ResolvedState -eq 'Installed')
                    Type        = 'Program'
                })
            }
        }
    }
    catch {
        Write-Log -Level Warn -Message "Failed to query CCM_Program: $($_.Exception.Message)"
    }

    # ------------------------------------------------------------------
    # 4. Combine and filter out already-installed deployments
    # ------------------------------------------------------------------
    $allDeployments = @($applications) + @($programs)

    $available = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($dep in $allDeployments) {
        if ($dep.IsInstalled) {
            Write-Log -Level Info -Message "Deployment '$($dep.Name)' already installed — toast suppressed."
        }
        else {
            $available.Add($dep)
        }
    }

    return $available
}
