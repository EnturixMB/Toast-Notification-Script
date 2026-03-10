<#
.SYNOPSIS
    Removes the Toast Notification POC from the system.

.DESCRIPTION
    Cleanup script that reverses the deployment performed by Deploy-POCEnvironment.ps1.
    Unregisters the scheduled task, removes deployed files, and optionally
    clears per-user tracking data.

    Must be run as Administrator.

.PARAMETER KeepTrackingData
    When specified, preserves the per-user ShownToasts.json tracking file
    in %APPDATA%\ToastNotificationScript.

.PARAMETER TargetPath
    Target installation directory to remove. Defaults to C:\ProgramData\ToastNotification.

.EXAMPLE
    .\Remove-POCEnvironment.ps1
    Removes everything including tracking data.

.EXAMPLE
    .\Remove-POCEnvironment.ps1 -KeepTrackingData
    Removes deployment but preserves tracking data.

.NOTES
    Requires Administrator privileges.
#>

[CmdletBinding()]
param(
    [switch]$KeepTrackingData,
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

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Toast Notification POC - Removal Script" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# Step 1: Unregister the Scheduled Task
# =============================================================================
Write-Host "  Step 1: Removing scheduled task..." -ForegroundColor White

$TaskName = "ToastNotification-SoftwareCenter"
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "    [OK] Scheduled task '$TaskName' removed." -ForegroundColor Green
}
else {
    Write-Host "    [OK] Scheduled task '$TaskName' was not registered." -ForegroundColor Gray
}

# =============================================================================
# Step 2: Remove deployed files
# =============================================================================
Write-Host ""
Write-Host "  Step 2: Removing deployed files..." -ForegroundColor White

if (Test-Path $TargetPath) {
    Remove-Item -Path $TargetPath -Recurse -Force
    Write-Host "    [OK] Removed: $TargetPath" -ForegroundColor Green
}
else {
    Write-Host "    [OK] Directory not found (already removed): $TargetPath" -ForegroundColor Gray
}

# =============================================================================
# Step 3: Remove per-user tracking data (optional)
# =============================================================================
Write-Host ""
Write-Host "  Step 3: Cleaning up tracking data..." -ForegroundColor White

if (-not $KeepTrackingData) {
    if (-not [string]::IsNullOrEmpty($env:APPDATA)) {
        $trackingDir = Join-Path $env:APPDATA "ToastNotificationScript"
        if (Test-Path $trackingDir) {
            Remove-Item -Path $trackingDir -Recurse -Force
            Write-Host "    [OK] Removed tracking data: $trackingDir" -ForegroundColor Green
        }
        else {
            Write-Host "    [OK] No tracking data found." -ForegroundColor Gray
        }
    }
    else {
        Write-Host "    [SKIP] APPDATA not available." -ForegroundColor Yellow
    }
}
else {
    Write-Host "    [SKIP] Tracking data preserved (-KeepTrackingData)." -ForegroundColor Yellow
}

# =============================================================================
# Summary
# =============================================================================
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Removal COMPLETE" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  The POC environment has been removed from this system." -ForegroundColor White
Write-Host "  To redeploy, run Deploy-POCEnvironment.ps1 again." -ForegroundColor Gray
Write-Host ""
