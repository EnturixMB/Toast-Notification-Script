<#
.SYNOPSIS
    Validation script for testing the Toast Notification POC without a live SCCM environment.

.DESCRIPTION
    Simulates the full orchestrator flow using mock deployment data.
    For each deployment it parses [TOAST-BEGIN] blocks, generates XML configs,
    and reports whether a toast would be shown or suppressed (and why).

    Outputs a colour-coded per-deployment status and an overall summary.

.PARAMETER ShowToast
    When specified, actually invokes Remediate-ToastNotification.ps1 with the
    generated XML for each qualifying deployment.
    Requires the script and images to be in place at C:\ProgramData\ToastNotification\.

.EXAMPLE
    .\Test-ToastPOC.ps1
    Runs the full simulation with mock data and prints results.

.EXAMPLE
    .\Test-ToastPOC.ps1 -ShowToast
    Runs the simulation and displays real toast notifications.

.NOTES
    POC Step 9 - End-to-End Validation
#>

[CmdletBinding()]
param(
    [switch]$ShowToast
)

# =============================================================================
# Configuration
# =============================================================================
$BasePath           = "C:\ProgramData\ToastNotification"
$BaseTemplatePath   = Join-Path $PSScriptRoot "config-toast-base-template.xml"
$RemediateScriptPath = "$BasePath\Remediate-ToastNotification.ps1"

# =============================================================================
# Dot-source the standalone block parser
# =============================================================================
. (Join-Path $PSScriptRoot "Get-ToastBlockFromDescription.ps1")

# =============================================================================
# Function: New-ToastXmlFromTags (inline copy from Invoke-ToastFromSoftwareCenter.ps1)
# =============================================================================
function New-ToastXmlFromTags {
    param(
        [hashtable]$Tags,
        [string]$BaseTemplatePath
    )

    [xml]$xml = Get-Content -Path $BaseTemplatePath -Encoding UTF8
    $langNode = $xml.Configuration.'en-US'
    $ImageBasePath = "C:\ProgramData\ToastNotification\Images"

    # Urgency -> image selection
    if ($Tags.ContainsKey('Urgency')) {
        $urgency = $Tags['Urgency'].ToLower()
        switch ($urgency) {
            'info'     { $heroFile = 'hero-info.png';     $logoFile = 'logo-info.png'     }
            'warnung'  { $heroFile = 'hero-warnung.png';  $logoFile = 'logo-warnung.png'  }
            'kritisch' { $heroFile = 'hero-kritisch.png'; $logoFile = 'logo-kritisch.png' }
            default {
                Write-Warning "Unknown Urgency value '$urgency' - falling back to 'info'."
                $heroFile = 'hero-info.png'
                $logoFile = 'logo-info.png'
            }
        }
        $heroPath = "$ImageBasePath\$heroFile"
        $logoPath = "$ImageBasePath\$logoFile"
        ($xml.Configuration.Option | Where-Object { $_.Name -eq 'HeroImageName' }).Value = $heroPath
        ($xml.Configuration.Option | Where-Object { $_.Name -eq 'LogoImageName' }).Value = $logoPath
    }

    # Tag-to-XML text mapping
    $textMapping = @{
        'Headline'      = 'HeaderText'
        'Title'         = 'TitleText'
        'Description'   = 'BodyText1'
        'Body2'         = 'BodyText2'
        'Attribution'   = 'AttributionText'
        'ActionButton'  = 'ActionButton1'
        'ActionButton2' = 'ActionButton2'
        'DismissButton' = 'DismissButton'
    }

    foreach ($tagName in $textMapping.Keys) {
        if ($Tags.ContainsKey($tagName)) {
            $xmlTextName = $textMapping[$tagName]
            $textNode = $langNode.Text | Where-Object { $_.Name -eq $xmlTextName }
            if ($null -ne $textNode) {
                $textNode.InnerText = $Tags[$tagName]
            }
        }
    }

    if ($Tags.ContainsKey('ActionButton')) {
        $optNode = $xml.Configuration.Option | Where-Object { $_.Name -eq 'ActionButton1' }
        if ($null -ne $optNode) { $optNode.Enabled = 'True' }
    }
    if ($Tags.ContainsKey('ActionButton2')) {
        $optNode = $xml.Configuration.Option | Where-Object { $_.Name -eq 'ActionButton2' }
        if ($null -ne $optNode) { $optNode.Enabled = 'True' }
    }

    if ($Tags.ContainsKey('HeroImage')) {
        ($xml.Configuration.Option | Where-Object { $_.Name -eq 'HeroImageName' }).Value = $Tags['HeroImage']
    }
    if ($Tags.ContainsKey('LogoImage')) {
        ($xml.Configuration.Option | Where-Object { $_.Name -eq 'LogoImageName' }).Value = $Tags['LogoImage']
    }
    if ($Tags.ContainsKey('Scenario')) {
        ($xml.Configuration.Option | Where-Object { $_.Name -eq 'Scenario' }).Type = $Tags['Scenario']
    }
    if ($Tags.ContainsKey('Action')) {
        ($xml.Configuration.Option | Where-Object { $_.Name -eq 'Action1' }).Value = $Tags['Action']
    }
    if ($Tags.ContainsKey('Action2')) {
        ($xml.Configuration.Option | Where-Object { $_.Name -eq 'Action2' }).Value = $Tags['Action2']
    }

    return $xml
}

# =============================================================================
# Function: Test-ToastAlreadyShown (inline copy from Invoke-ToastFromSoftwareCenter.ps1)
# =============================================================================
function Test-ToastAlreadyShown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$DeploymentName,
        [Parameter(Mandatory=$true)]
        [string]$Description
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($DeploymentName + $Description)
        $hashBytes = $sha256.ComputeHash($bytes)
        $hash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
    }
    finally {
        $sha256.Dispose()
    }

    if ([string]::IsNullOrEmpty($env:APPDATA)) {
        return $false
    }
    $trackingDir  = Join-Path -Path $env:APPDATA -ChildPath "ToastNotificationScript"
    $trackingFile = Join-Path -Path $trackingDir  -ChildPath "ShownToasts.json"

    if (-not (Test-Path -Path $trackingFile)) {
        return $false
    }

    try {
        $jsonData = Get-Content -Path $trackingFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        return $false
    }

    if ($null -ne $jsonData -and $null -ne $jsonData.$hash) {
        return $true
    }

    return $false
}

# =============================================================================
# Helper: Format-XmlPretty  -  pretty-prints an [xml] object
# =============================================================================
function Format-XmlPretty {
    param([xml]$Xml)

    $stringWriter = [System.IO.StringWriter]::new()
    $xmlWriter    = [System.Xml.XmlTextWriter]::new($stringWriter)
    $xmlWriter.Formatting  = [System.Xml.Formatting]::Indented
    $xmlWriter.Indentation = 4
    try {
        $Xml.WriteTo($xmlWriter)
        $xmlWriter.Flush()
        return $stringWriter.ToString()
    }
    finally {
        $xmlWriter.Dispose()
        $stringWriter.Dispose()
    }
}

# =============================================================================
# 1. Simulate deployment data (bypass WMI)
# =============================================================================
$mockDeployments = @(
    [PSCustomObject]@{
        Name        = "7-Zip 24.09"
        Description = "Dieses Deployment installiert 7-Zip 24.09.`n`n[TOAST-BEGIN]`nt=Neue Software verfügbar`nd=7-Zip 24.09 steht bereit.`nu=warnung`n[TOAST-END]"
        IsInstalled = $false
    },
    [PSCustomObject]@{
        Name        = "Notepad++ 8.6"
        Description = "Standard text editor installation."
        IsInstalled = $false
    },
    [PSCustomObject]@{
        Name        = "VLC Media Player"
        Description = "[TOAST-BEGIN]`nt=VLC verfügbar`nd=Bitte installieren.`n[TOAST-END]"
        IsInstalled = $true
    }
)

# =============================================================================
# 2. Run through orchestrator logic step by step
# =============================================================================
Write-Host "`n=====================================================================" -ForegroundColor Cyan
Write-Host "  Test-ToastPOC - End-to-End Validation (Mock Data)" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan

# Summary counters
$totalDeployments       = $mockDeployments.Count
$withToastBlock         = 0
$suppressedInstalled    = 0
$suppressedDuplicate    = 0
$toastsDisplayed        = 0

$deploymentIndex = 0
foreach ($deployment in $mockDeployments) {
    $deploymentIndex++
    Write-Host "`n---------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Deployment $deploymentIndex/$totalDeployments : $($deployment.Name)" -ForegroundColor White
    Write-Host "---------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  IsInstalled : $($deployment.IsInstalled)" -ForegroundColor Gray

    # --- Check: already installed ---
    if ($deployment.IsInstalled) {
        # Still parse to count toast blocks before suppressing
        $tags = Get-ToastBlockFromDescription -Description $deployment.Description
        if ($null -ne $tags) {
            $withToastBlock++
        }
        $suppressedInstalled++
        Write-Host "  Status      : SUPPRESSED (already installed)" -ForegroundColor Yellow
        Write-Host "  [SKIP] Toast suppressed - software is already installed." -ForegroundColor Yellow
        continue
    }

    # --- Parse [TOAST-BEGIN] block ---
    $tags = Get-ToastBlockFromDescription -Description $deployment.Description
    if ($null -eq $tags) {
        Write-Host "  Status      : SKIPPED (no [TOAST-BEGIN] block)" -ForegroundColor DarkYellow
        Write-Host "  [SKIP] No toast metadata found in description." -ForegroundColor DarkYellow
        continue
    }

    $withToastBlock++

    # Display parsed tags
    Write-Host "`n  Parsed Tags:" -ForegroundColor Green
    foreach ($key in ($tags.Keys | Sort-Object)) {
        Write-Host "    $key = $($tags[$key])" -ForegroundColor Green
    }

    # --- Check: duplicate prevention ---
    $isDuplicate = Test-ToastAlreadyShown -DeploymentName $deployment.Name -Description $deployment.Description
    if ($isDuplicate) {
        $suppressedDuplicate++
        Write-Host "`n  Status      : SUPPRESSED (duplicate - already shown)" -ForegroundColor Yellow
        Write-Host "  [SKIP] Toast was already displayed for this deployment." -ForegroundColor Yellow
        continue
    }

    # --- Generate XML ---
    $xml = New-ToastXmlFromTags -Tags $tags -BaseTemplatePath $BaseTemplatePath
    $prettyXml = Format-XmlPretty -Xml $xml

    Write-Host "`n  Generated XML:" -ForegroundColor Cyan
    foreach ($line in ($prettyXml -split '\r?\n')) {
        Write-Host "    $line" -ForegroundColor Cyan
    }

    # --- Show or simulate toast ---
    if ($ShowToast) {
        $tempConfig = Join-Path ([System.IO.Path]::GetTempPath()) "toast-config-$(Get-Random).xml"
        $xml.Save($tempConfig)
        try {
            Write-Host "`n  [LIVE] Invoking Remediate-ToastNotification.ps1..." -ForegroundColor Magenta
            powershell.exe -ExecutionPolicy Bypass -Command "& '$RemediateScriptPath' -Config '$tempConfig'"
            Write-Host "  [PASS] Toast displayed for '$($deployment.Name)'." -ForegroundColor Green
        }
        catch {
            Write-Host "  [FAIL] Failed to invoke toast: $_" -ForegroundColor Red
        }
        finally {
            if (Test-Path -Path $tempConfig) {
                Remove-Item -Path $tempConfig -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        Write-Host "`n  [PASS] Toast WOULD be displayed (dry run)." -ForegroundColor Green
    }

    $toastsDisplayed++
}

# =============================================================================
# 3. Output Summary
# =============================================================================
Write-Host "`n=====================================================================" -ForegroundColor Cyan
Write-Host "  Summary" -ForegroundColor Cyan
Write-Host "=====================================================================" -ForegroundColor Cyan
Write-Host "  Total deployments found          : $totalDeployments" -ForegroundColor White
Write-Host "  Deployments with [TOAST-BEGIN]    : $withToastBlock" -ForegroundColor White
Write-Host "  Toasts suppressed (installed)     : $suppressedInstalled" -ForegroundColor $(if ($suppressedInstalled -gt 0) { 'Yellow' } else { 'White' })
Write-Host "  Toasts suppressed (duplicate)     : $suppressedDuplicate" -ForegroundColor $(if ($suppressedDuplicate -gt 0) { 'Yellow' } else { 'White' })
Write-Host "  Toasts displayed                  : $toastsDisplayed" -ForegroundColor $(if ($toastsDisplayed -gt 0) { 'Green' } else { 'White' })
Write-Host "=====================================================================`n" -ForegroundColor Cyan
