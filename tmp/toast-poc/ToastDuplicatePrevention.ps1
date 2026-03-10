function Test-ToastAlreadyShown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$DeploymentName,
        [Parameter(Mandatory=$true)]
        [string]$Description
    )

    # Compute SHA256 hash of DeploymentName + Description
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($DeploymentName + $Description)
        $hashBytes = $sha256.ComputeHash($bytes)
        $hash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
    }
    finally {
        $sha256.Dispose()
    }

    # Read the tracking file
    if ([string]::IsNullOrEmpty($env:APPDATA)) {
        Write-Warning "APPDATA environment variable is not set. Cannot check toast tracking."
        return $false
    }
    $trackingDir = Join-Path -Path $env:APPDATA -ChildPath "ToastNotificationScript"
    $trackingFile = Join-Path -Path $trackingDir -ChildPath "ShownToasts.json"

    if (-NOT(Test-Path -Path $trackingFile)) {
        return $false
    }

    try {
        $jsonData = Get-Content -Path $trackingFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        return $false
    }

    # Check if the hash exists in the JSON data
    if ($null -ne $jsonData -and $null -ne $jsonData.$hash) {
        return $true
    }

    return $false
}

function Set-ToastShown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$DeploymentName,
        [Parameter(Mandatory=$true)]
        [string]$Description
    )

    # Compute SHA256 hash of DeploymentName + Description
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($DeploymentName + $Description)
        $hashBytes = $sha256.ComputeHash($bytes)
        $hash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
    }
    finally {
        $sha256.Dispose()
    }

    # Read the existing tracking file or create empty structure if missing
    if ([string]::IsNullOrEmpty($env:APPDATA)) {
        throw "APPDATA environment variable is not set. Cannot store toast tracking data."
    }
    $trackingDir = Join-Path -Path $env:APPDATA -ChildPath "ToastNotificationScript"
    $trackingFile = Join-Path -Path $trackingDir -ChildPath "ShownToasts.json"

    if (-NOT(Test-Path -Path $trackingDir)) {
        try {
            New-Item -Path $trackingDir -ItemType Directory -Force | Out-Null
        }
        catch {
            throw "Failed to create tracking directory: $_"
        }
    }

    $jsonData = $null
    if (Test-Path -Path $trackingFile) {
        try {
            $jsonData = Get-Content -Path $trackingFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
        }
        catch {
            $jsonData = $null
        }
    }

    if ($null -eq $jsonData) {
        $jsonData = [PSCustomObject]@{}
    }

    # Add or update the entry
    $entry = [PSCustomObject]@{
        DeploymentName = $DeploymentName
        Description    = $Description
        ShownAt        = Get-Date -Format s
    }

    if ($null -ne $jsonData.$hash) {
        $jsonData.$hash = $entry
    }
    else {
        $jsonData | Add-Member -MemberType NoteProperty -Name $hash -Value $entry -Force
    }

    # Save back to the JSON file
    try {
        $jsonData | ConvertTo-Json -Depth 10 | Set-Content -Path $trackingFile -Encoding UTF8 -Force -ErrorAction Stop
    }
    catch {
        throw "Failed to save tracking file: $_"
    }
}
