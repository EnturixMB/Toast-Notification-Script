<#
.SYNOPSIS
    Get-AvailableDeploymentFields.ps1 - Discovery script for Software Center deployment fields

.DESCRIPTION
    Queries the SCCM/MEMCM client WMI namespace (root\ccm\ClientSDK) to discover
    all available properties on CCM_Application and CCM_Program WMI classes.

    This is an exploratory script intended to help understand what data is available
    from Software Center deployments before building automation on top of it.

    The script performs read-only WMI queries and does not modify any data.

.EXAMPLE
    .\Get-AvailableDeploymentFields.ps1

.OUTPUTS
    Displays:
    - All properties of the CCM_Application WMI class with their types
    - All properties of the CCM_Program WMI class with their types
    - Sample deployment data for each class (if deployments exist on the device)

.NOTES
    Script Name    : Get-AvailableDeploymentFields.ps1
    Version        : 1.0.0
    Created        : March 2026

    Requirements:
    - Windows 10 or later / Windows 11
    - PowerShell 5.1 or later
    - SCCM/MEMCM client installed on the device
    - User context execution (not SYSTEM)

    WMI Details:
    - Namespace: root\ccm\ClientSDK
    - Classes:   CCM_Application (Applications), CCM_Program (Packages/Programs)
    - All queries are read-only

.LINK
    https://github.com/imabdk/Toast-Notification-Script
#>

[CmdletBinding()]
param()

# ============================================================
# Configuration
# ============================================================
$WmiNamespace = "root\ccm\ClientSDK"
$WmiClasses   = @("CCM_Application", "CCM_Program")

# ============================================================
# Helper Functions
# ============================================================
function Write-Header {
    param([string]$Title)
    $separator = "=" * 70
    Write-Output ""
    Write-Output $separator
    Write-Output " $Title"
    Write-Output $separator
}

function Write-SubHeader {
    param([string]$Title)
    $separator = "-" * 70
    Write-Output ""
    Write-Output $separator
    Write-Output " $Title"
    Write-Output $separator
}

# ============================================================
# Pre-flight: Verify SCCM Client
# ============================================================
Write-Header "Software Center Deployment Field Discovery"
Write-Output " Namespace: $WmiNamespace"
Write-Output " Date:      $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output " User:      $env:USERNAME"

try {
    $null = Get-CimClass -Namespace $WmiNamespace -ErrorAction Stop
    Write-Output " Status:    SCCM client namespace found"
}
catch {
    Write-Warning "Cannot access WMI namespace '$WmiNamespace'."
    Write-Warning "The SCCM/MEMCM client may not be installed on this device."
    Write-Warning "Error: $($_.Exception.Message)"
    exit 1
}

# ============================================================
# Query Each WMI Class
# ============================================================
foreach ($className in $WmiClasses) {

    Write-Header "WMI Class: $className"

    # ----------------------------------------------------------
    # Class Schema: List all properties and their types
    # ----------------------------------------------------------
    Write-SubHeader "Available Properties (Schema)"

    try {
        $classObj = Get-CimClass -Namespace $WmiNamespace -ClassName $className -ErrorAction Stop

        if ($null -eq $classObj) {
            Write-Warning "Class '$className' not found in namespace '$WmiNamespace'."
            continue
        }

        $properties = $classObj.CimClassProperties | Sort-Object Name
        $propertyCount = ($properties | Measure-Object).Count

        Write-Output " Total properties: $propertyCount"
        Write-Output ""
        Write-Output (" {0,-40} {1,-20} {2}" -f "Property Name", "Type", "Is Array")
        Write-Output (" {0,-40} {1,-20} {2}" -f ("-" * 40), ("-" * 20), ("-" * 8))

        foreach ($prop in $properties) {
            $isArray = if ($prop.CimType.ToString() -like '*Array') { "Yes" } else { "No" }
            Write-Output (" {0,-40} {1,-20} {2}" -f $prop.Name, $prop.CimType, $isArray)
        }
    }
    catch {
        Write-Warning "Failed to retrieve schema for class '$className': $($_.Exception.Message)"
        continue
    }

    # ----------------------------------------------------------
    # Instances: Show available deployments
    # ----------------------------------------------------------
    Write-SubHeader "Available Deployments ($className)"

    try {
        $instances = Get-CimInstance -Namespace $WmiNamespace -ClassName $className -ErrorAction Stop

        if ($null -eq $instances) {
            Write-Output " No deployments found for $className."
            continue
        }

        $instanceList = @($instances)
        Write-Output " Found $($instanceList.Count) deployment(s)"

        foreach ($instance in $instanceList) {
            Write-Output ""
            Write-Output " --- Deployment ---"

            foreach ($prop in ($properties | Sort-Object Name)) {
                $value = $instance.($prop.Name)

                # Format the value for display
                if ($null -eq $value) {
                    $displayValue = "(null)"
                }
                elseif ($value -is [array]) {
                    $displayValue = "[" + ($value -join ", ") + "]"
                }
                else {
                    $displayValue = $value.ToString()
                    # Truncate very long values for readability
                    if ($displayValue.Length -gt 200) {
                        $displayValue = $displayValue.Substring(0, 200) + "..."
                    }
                }

                Write-Output ("   {0,-40} : {1}" -f $prop.Name, $displayValue)
            }
        }
    }
    catch {
        Write-Warning "Failed to query instances of '$className': $($_.Exception.Message)"
    }
}

Write-Header "Discovery Complete"
Write-Output " Review the properties above to determine which fields are useful"
Write-Output " for building Software Center toast notification integration."
Write-Output ""
