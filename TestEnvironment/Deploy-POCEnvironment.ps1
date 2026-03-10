<#
.SYNOPSIS
    Deploys the Toast Notification POC to C:\ProgramData\ToastNotification\.

.DESCRIPTION
    Automated setup script for the Software Center Toast Notification POC.
    Copies all required scripts, configuration, and images from the repository
    to the target directory and optionally registers the scheduled task.

    Must be run as Administrator.

.PARAMETER SkipScheduledTask
    When specified, skips the registration of the scheduled task.
    Useful when you only want to deploy files and test manually.

.PARAMETER TargetPath
    Target installation directory. Defaults to C:\ProgramData\ToastNotification.

.EXAMPLE
    .\Deploy-POCEnvironment.ps1
    Deploys all files and registers the scheduled task.

.EXAMPLE
    .\Deploy-POCEnvironment.ps1 -SkipScheduledTask
    Deploys files only, without registering the scheduled task.

.NOTES
    Run this script from the TestEnvironment folder inside the repository.
    Requires Administrator privileges.
#>

[CmdletBinding()]
param(
    [switch]$SkipScheduledTask,
    [string]$TargetPath = "C:\ProgramData\ToastNotification"
)

# =============================================================================
# Admin Privilege Check
# =============================================================================
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator. Right-click PowerShell and select 'Run as Administrator'."
    exit 1
}

# =============================================================================
# Resolve paths
# =============================================================================
$RepoRoot = Split-Path -Path $PSScriptRoot -Parent

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Toast Notification POC - Deployment Script" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Repository Root : $RepoRoot" -ForegroundColor Gray
Write-Host "  Target Path     : $TargetPath" -ForegroundColor Gray
Write-Host ""

# =============================================================================
# Validate source files exist
# =============================================================================
$requiredFiles = @(
    "Remediate-ToastNotification.ps1",
    "Invoke-ToastFromSoftwareCenter.ps1",
    "Get-ToastBlockFromDescription.ps1",
    "Get-SoftwareCenterDeployments.ps1",
    "Register-ToastScheduledTask.ps1",
    "Test-ToastPOC.ps1",
    "config-toast-base-template.xml"
)

$requiredImages = @(
    "hero-info.png",
    "hero-warnung.png",
    "hero-kritisch.png",
    "logo-info.png",
    "logo-warnung.png",
    "logo-kritisch.png"
)

$missingFiles = @()
foreach ($file in $requiredFiles) {
    if (-not (Test-Path (Join-Path $RepoRoot $file))) {
        $missingFiles += $file
    }
}
foreach ($img in $requiredImages) {
    if (-not (Test-Path (Join-Path $RepoRoot "Images\$img"))) {
        $missingFiles += "Images\$img"
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Error "Missing required source files:`n  $($missingFiles -join "`n  ")"
    Write-Error "Make sure you run this script from the TestEnvironment folder inside the repository."
    exit 1
}

Write-Host "  [OK] All source files found." -ForegroundColor Green

# =============================================================================
# Step 1: Create target directories
# =============================================================================
Write-Host ""
Write-Host "  Step 1: Creating target directories..." -ForegroundColor White

$imagesPath = Join-Path $TargetPath "Images"
$logsPath   = Join-Path $TargetPath "Logs"

foreach ($dir in @($TargetPath, $imagesPath, $logsPath)) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
        Write-Host "    Created: $dir" -ForegroundColor Green
    }
    else {
        Write-Host "    Exists:  $dir" -ForegroundColor Yellow
    }
}

# =============================================================================
# Step 2: Copy scripts and configuration
# =============================================================================
Write-Host ""
Write-Host "  Step 2: Copying scripts and configuration..." -ForegroundColor White

foreach ($file in $requiredFiles) {
    $source = Join-Path $RepoRoot $file
    $destination = Join-Path $TargetPath $file
    Copy-Item -Path $source -Destination $destination -Force
    Write-Host "    Copied: $file" -ForegroundColor Green
}

# =============================================================================
# Step 3: Copy images
# =============================================================================
Write-Host ""
Write-Host "  Step 3: Copying images..." -ForegroundColor White

foreach ($img in $requiredImages) {
    $source = Join-Path $RepoRoot "Images\$img"
    $destination = Join-Path $imagesPath $img
    Copy-Item -Path $source -Destination $destination -Force
    Write-Host "    Copied: Images\$img" -ForegroundColor Green
}

# =============================================================================
# Step 4: Register Scheduled Task (optional)
# =============================================================================
if (-not $SkipScheduledTask) {
    Write-Host ""
    Write-Host "  Step 4: Registering scheduled task..." -ForegroundColor White

    $registerScript = Join-Path $TargetPath "Register-ToastScheduledTask.ps1"
    try {
        & $registerScript
        Write-Host "    [OK] Scheduled task registered." -ForegroundColor Green
    }
    catch {
        Write-Warning "    Failed to register scheduled task: $_"
        Write-Host "    You can register it manually later by running:" -ForegroundColor Yellow
        Write-Host "      & '$registerScript'" -ForegroundColor Yellow
    }
}
else {
    Write-Host ""
    Write-Host "  Step 4: Skipped scheduled task registration (-SkipScheduledTask)." -ForegroundColor Yellow
}

# =============================================================================
# Step 5: Validate deployment
# =============================================================================
Write-Host ""
Write-Host "  Step 5: Validating deployment..." -ForegroundColor White

$allValid = $true
foreach ($file in $requiredFiles) {
    $target = Join-Path $TargetPath $file
    if (Test-Path $target) {
        Write-Host "    [OK] $file" -ForegroundColor Green
    }
    else {
        Write-Host "    [MISSING] $file" -ForegroundColor Red
        $allValid = $false
    }
}
foreach ($img in $requiredImages) {
    $target = Join-Path $imagesPath $img
    if (Test-Path $target) {
        Write-Host "    [OK] Images\$img" -ForegroundColor Green
    }
    else {
        Write-Host "    [MISSING] Images\$img" -ForegroundColor Red
        $allValid = $false
    }
}

# =============================================================================
# Summary
# =============================================================================
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
if ($allValid) {
    Write-Host "  Deployment SUCCESSFUL" -ForegroundColor Green
}
else {
    Write-Host "  Deployment COMPLETED WITH WARNINGS" -ForegroundColor Yellow
}
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Deployed to: $TargetPath" -ForegroundColor White
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor White
Write-Host "    1. Run a dry-run test (no real toasts):" -ForegroundColor Gray
Write-Host "       cd '$TargetPath'" -ForegroundColor Gray
Write-Host "       .\Test-ToastPOC.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "    2. Run a live test (shows real toast notifications):" -ForegroundColor Gray
Write-Host "       .\Test-ToastPOC.ps1 -ShowToast" -ForegroundColor Gray
Write-Host ""
Write-Host "    3. Test with live Software Center data:" -ForegroundColor Gray
Write-Host "       .\Invoke-ToastFromSoftwareCenter.ps1 -TestMode" -ForegroundColor Gray
Write-Host ""
Write-Host "  See HOW-TO-TEST-POC.md for the complete testing guide." -ForegroundColor White
Write-Host ""
