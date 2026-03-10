<#
.SYNOPSIS
    Register-ToastScheduledTask.ps1 - Registers a Scheduled Task for Toast Notifications

.DESCRIPTION
    Registers a Windows Scheduled Task that triggers the toast orchestrator script
    (Invoke-ToastFromSoftwareCenter.ps1) on user logon and workstation unlock.

    The task runs in the context of the currently logged-on user with limited
    privileges and is configured to time out after 5 minutes.

    This script must be run with Administrator (elevated) privileges because
    registering scheduled tasks requires administrative rights.

.PARAMETER Unregister
    When specified, removes the scheduled task instead of registering it.

.EXAMPLE
    .\Register-ToastScheduledTask.ps1
    Registers the scheduled task with logon and unlock triggers.

.EXAMPLE
    .\Register-ToastScheduledTask.ps1 -Unregister
    Removes the scheduled task if it exists.

.NOTES
    Script Name    : Register-ToastScheduledTask.ps1
    Requires       : Administrator privileges
    Task triggers  : AtLogon (any user), SessionUnlock

.LINK
    https://github.com/imabdk/Toast-Notification-Script
#>

[CmdletBinding()]
param(
    [switch]$Unregister
)

# =============================================================================
# Constants
# =============================================================================
$TaskName = "ToastNotification-SoftwareCenter"
$ScriptPath = "C:\ProgramData\ToastNotification\Invoke-ToastFromSoftwareCenter.ps1"

# =============================================================================
# Admin Privilege Check
# Scheduled task registration requires an elevated session.
# =============================================================================
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator. Please re-launch PowerShell with elevated privileges."
    exit 1
}

# =============================================================================
# Unregister Mode
# If -Unregister is specified, remove the task and exit.
# =============================================================================
if ($Unregister) {
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Output "Scheduled task '$TaskName' has been removed."
    }
    else {
        Write-Output "Scheduled task '$TaskName' does not exist. Nothing to remove."
    }
    exit 0
}

# =============================================================================
# Remove Existing Task
# If a task with the same name already exists, unregister it before
# re-registering to ensure a clean configuration.
# =============================================================================
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Output "Existing scheduled task '$TaskName' found. Removing before re-registering..."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# =============================================================================
# Trigger 1: AtLogon
# Fires when any user logs on to the machine.
# =============================================================================
$triggerLogon = New-ScheduledTaskTrigger -AtLogOn

# =============================================================================
# Trigger 2: SessionUnlock
# Fires when any user unlocks the workstation.
# Uses CIM to create a SessionStateChangeTrigger with StateChange = SessionUnlock.
# SessionUnlock corresponds to StateChange value 8.
# =============================================================================
$triggerClass = Get-CimClass -ClassName MSFT_TaskSessionStateChangeTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
$triggerUnlock = New-CimInstance -CimClass $triggerClass -ClientOnly -Property @{
    StateChange = [Int32]8  # SessionUnlock
}

# =============================================================================
# Action
# Launches PowerShell to execute the toast orchestrator script.
#   -ExecutionPolicy Bypass  : Ensures the script runs regardless of policy
#   -WindowStyle Hidden      : Runs without a visible console window
#   -File                    : Points to the orchestrator script
# =============================================================================
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""

# =============================================================================
# Principal
# Runs the task as the currently logged-on user (BUILTIN\Users group)
# with limited (non-elevated) privileges.
# =============================================================================
$principal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Users" -RunLevel Limited

# =============================================================================
# Settings
#   RunOnlyIfLoggedOn        : Task runs only when a user session is active
#   AllowDemandStart         : Allows manual triggering of the task
#   ExecutionTimeLimit       : Kills the task if it runs longer than 5 minutes
#   DisallowStartIfOnBatteries : Allows the task to start on battery power
#   StopIfGoingOnBatteries   : Keeps the task running if switching to battery
# =============================================================================
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

# =============================================================================
# Register the Scheduled Task
# Combines triggers, action, principal, and settings into a single task.
# =============================================================================
Register-ScheduledTask `
    -TaskName $TaskName `
    -Trigger $triggerLogon, $triggerUnlock `
    -Action $action `
    -Principal $principal `
    -Settings $settings `
    -Description "Displays toast notifications for available Software Center deployments on logon and workstation unlock." `
    -Force

Write-Output "Scheduled task '$TaskName' registered successfully."
