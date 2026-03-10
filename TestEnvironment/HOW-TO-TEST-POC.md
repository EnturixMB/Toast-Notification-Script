# How To Test the Software Center Toast Notification POC

Step-by-step guide for testing the complete POC workflow on a **Windows 11** machine with the **MCM/MECM client** installed.

---

## Prerequisites

| Requirement | Details |
|---|---|
| **OS** | Windows 10 1709+ or Windows 11 |
| **PowerShell** | 5.1 or higher (built-in) |
| **MCM Client** | SCCM/MECM Configuration Manager client installed (for live testing) |
| **Privileges** | Administrator rights (for deployment and scheduled task registration) |

---

## What Is in This Test Kit

| File | Purpose |
|---|---|
| `Deploy-POCEnvironment.ps1` | Automated setup – copies all scripts, images, and config to `C:\ProgramData\ToastNotification\` and registers the scheduled task |
| `Remove-POCEnvironment.ps1` | Cleanup – unregisters the scheduled task and removes all deployed files |
| `HOW-TO-TEST-POC.md` | This guide |

The deployment script copies these files from the repository root:

| Script | Role |
|---|---|
| `Remediate-ToastNotification.ps1` | Core toast engine (displays the notification) |
| `Invoke-ToastFromSoftwareCenter.ps1` | Orchestrator (queries Software Center, parses descriptions, invokes toast engine) |
| `Get-ToastBlockFromDescription.ps1` | Parser for `[TOAST-BEGIN]…[TOAST-END]` blocks in deployment descriptions |
| `Get-SoftwareCenterDeployments.ps1` | WMI helper to query SCCM deployments |
| `Register-ToastScheduledTask.ps1` | Registers the scheduled task (logon + unlock triggers) |
| `Test-ToastPOC.ps1` | POC validation with mock data (no live SCCM needed) |
| `config-toast-base-template.xml` | Base XML configuration template (German defaults) |
| `Images\` (6 files) | Urgency-based hero and logo images (Info, Warnung, Kritisch) |

---

## Step 1 – Deploy the POC Environment

Open **PowerShell as Administrator** and run:

```powershell
cd "<path-to-repo>\TestEnvironment"
.\Deploy-POCEnvironment.ps1
```

This will:
1. Create `C:\ProgramData\ToastNotification\` with `Images\` and `Logs\` subdirectories
2. Copy all required scripts and the config template
3. Copy the six urgency-based images
4. Register the scheduled task `ToastNotification-SoftwareCenter`

> **Tip:** To deploy files only without registering the scheduled task, use:
> ```powershell
> .\Deploy-POCEnvironment.ps1 -SkipScheduledTask
> ```

After deployment, verify the directory structure:

```
C:\ProgramData\ToastNotification\
├── Remediate-ToastNotification.ps1
├── Invoke-ToastFromSoftwareCenter.ps1
├── Get-ToastBlockFromDescription.ps1
├── Get-SoftwareCenterDeployments.ps1
├── Register-ToastScheduledTask.ps1
├── Test-ToastPOC.ps1
├── config-toast-base-template.xml
├── Images\
│   ├── hero-info.png
│   ├── hero-warnung.png
│   ├── hero-kritisch.png
│   ├── logo-info.png
│   ├── logo-warnung.png
│   └── logo-kritisch.png
└── Logs\
```

---

## Step 2 – Test with Mock Data (Dry Run, No SCCM Needed)

This test uses three simulated deployments to validate the parsing, XML generation, and suppression logic. No real toast notifications are displayed.

```powershell
cd "C:\ProgramData\ToastNotification"
.\Test-ToastPOC.ps1
```

**Expected output:**

| Mock Deployment | Expected Result |
|---|---|
| 7-Zip 24.09 | ✅ PASS – has `[TOAST-BEGIN]` block, not installed, toast would be displayed |
| Notepad++ 8.6 | ⏭ SKIP – no `[TOAST-BEGIN]` block in description |
| VLC Media Player | 🟡 SUPPRESSED – has `[TOAST-BEGIN]` block but already installed |

The script prints a colour-coded summary at the end.

---

## Step 3 – Test with Real Toast Notifications (Mock Data)

Same mock data as Step 2, but actually shows a real Windows toast notification on screen:

```powershell
.\Test-ToastPOC.ps1 -ShowToast
```

You should see a Windows notification pop up for the 7-Zip deployment with:
- **Title:** Neue Software verfügbar
- **Body:** 7-Zip 24.09 steht bereit.
- **Buttons:** "Software Center öffnen" and "Schließen"
- **Image:** Warning-level hero/logo (because `u=warnung` is set)

---

## Step 4 – Test with Live Software Center Data

If your MCM client has deployments available, test the full orchestrator:

```powershell
.\Invoke-ToastFromSoftwareCenter.ps1 -TestMode
```

The `-TestMode` flag disables duplicate prevention, so you can run the script repeatedly without toasts being suppressed.

**What it does:**
1. Queries `CCM_Application` and `CCM_Program` via WMI
2. For each uninstalled deployment with a `[TOAST-BEGIN]` block, generates an XML config and displays a toast
3. Processes up to 3 deployments per run

> **Note:** If no deployments have `[TOAST-BEGIN]` blocks in their descriptions, no toasts will appear. See Step 5 to add test blocks.

---

## Step 5 – Add a [TOAST-BEGIN] Block to a Deployment

In the **SCCM/MECM Console**, edit a deployment's **Description** field and add a toast block at the bottom:

### Minimal Example (2 lines)

```
[TOAST-BEGIN]
t=Neue Software verfügbar
[TOAST-END]
```

### Full Example (all options)

```
[TOAST-BEGIN]
t=Neue Software verfügbar
d=7-Zip 24.09 steht zur Installation bereit.
u=warnung
h=IT-Abteilung
b2=Bitte installieren Sie die Software zeitnah.
at=IT-Support
ab=Jetzt installieren
a=softwarecenter:Page=InstallationStatus
db=Später
[TOAST-END]
```

### Tag Reference (Short → Full)

| Short | Full Name | Description |
|---|---|---|
| `h` | Headline | Small header text above the title |
| `t` | Title | Main notification title |
| `d` | Description | Primary body text |
| `b2` | Body2 | Secondary body text |
| `at` | Attribution | Attribution text at the bottom |
| `u` | Urgency | Image set: `info`, `warnung`, or `kritisch` |
| `sc` | Scenario | Toast behavior: `reminder`, `short`, `long`, or `alarm` |
| `ab` | ActionButton | Text for button 1 |
| `a` | Action | URL/protocol for button 1 (e.g., `softwarecenter:Page=Applications`) |
| `ab2` | ActionButton2 | Text for button 2 |
| `a2` | Action2 | URL/protocol for button 2 |
| `db` | DismissButton | Text for the close button |
| `hi` | HeroImage | Custom hero image path (overrides urgency) |
| `li` | LogoImage | Custom logo image path (overrides urgency) |
| `dl` | Deadline | Deadline date (reserved for future use) |
| `sd` | StartDate | Start date (reserved for future use) |

> **Tip:** All tags are optional. Defaults are applied from `config-toast-base-template.xml`. At minimum, only `t` (Title) is recommended.

---

## Step 6 – Test Scheduled Task Triggers

The scheduled task `ToastNotification-SoftwareCenter` fires on:
- **User logon** – when any user signs in
- **Workstation unlock** – when the user unlocks the screen (Win+L → unlock)

### Test by Manual Trigger

```powershell
# Open Task Scheduler and trigger manually:
Get-ScheduledTask -TaskName "ToastNotification-SoftwareCenter" | Start-ScheduledTask
```

### Test by Lock/Unlock

1. Press **Win + L** to lock the workstation
2. Sign back in
3. The toast orchestrator runs and checks for deployments with `[TOAST-BEGIN]` blocks

### Verify the Scheduled Task Exists

```powershell
Get-ScheduledTask -TaskName "ToastNotification-SoftwareCenter" | Format-List TaskName, State, Description
```

---

## Step 7 – Check Logs

Logs are written to `C:\ProgramData\ToastNotification\Logs\SoftwareCenterToast.log`:

```powershell
Get-Content "C:\ProgramData\ToastNotification\Logs\SoftwareCenterToast.log"
```

Each entry is timestamped and shows:
- Which deployments were found
- Which toasts were displayed or suppressed (and why)
- Any errors encountered

---

## Step 8 – Reset Duplicate Tracking

If you want to re-show a toast that was already displayed, clear the tracking data:

```powershell
$trackingFile = Join-Path $env:APPDATA "ToastNotificationScript\ShownToasts.json"
if (Test-Path $trackingFile) {
    Remove-Item $trackingFile -Force
    Write-Host "Tracking data cleared."
}
```

Or bypass duplicate checks entirely using `-TestMode`:

```powershell
.\Invoke-ToastFromSoftwareCenter.ps1 -TestMode
```

---

## Cleanup – Remove the POC Environment

When you are done testing, remove everything:

```powershell
cd "<path-to-repo>\TestEnvironment"
.\Remove-POCEnvironment.ps1
```

This will:
1. Unregister the scheduled task
2. Delete `C:\ProgramData\ToastNotification\` and all contents
3. Remove the per-user tracking data from `%APPDATA%\ToastNotificationScript`

> To keep the tracking data, use:
> ```powershell
> .\Remove-POCEnvironment.ps1 -KeepTrackingData
> ```

---

## Troubleshooting

### No toast appears

| Possible Cause | Fix |
|---|---|
| Script execution policy blocks `.ps1` | Run `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process` before testing |
| Images not found | Verify `C:\ProgramData\ToastNotification\Images\` contains all 6 PNG files |
| Custom notification app not registered | The first run of `Remediate-ToastNotification.ps1` registers the app. Run `Test-ToastPOC.ps1 -ShowToast` once |
| Focus Assist / Do Not Disturb enabled | Disable it in Windows Settings → System → Notifications |

### "SCCM client WMI namespace not available"

The MCM client is not installed or the WMI namespace `root\ccm\ClientSDK` is not accessible. This only affects live testing with `Invoke-ToastFromSoftwareCenter.ps1`. Mock testing with `Test-ToastPOC.ps1` works without the MCM client.

### Scheduled task does not fire

1. Check Task Scheduler → `ToastNotification-SoftwareCenter` exists and is **Ready**
2. Verify triggers: should have **AtLogon** and **SessionUnlock**
3. Check task history (right-click → Properties → History tab)

### Toast shows but with wrong images

Make sure the urgency tag value matches one of: `info`, `warnung`, `kritisch`. Any other value falls back to `info`.

---

## Quick Reference – Test Commands

```powershell
# Deploy the POC
.\Deploy-POCEnvironment.ps1

# Dry run with mock data (no real toasts)
cd "C:\ProgramData\ToastNotification"
.\Test-ToastPOC.ps1

# Live test with mock data (real toasts)
.\Test-ToastPOC.ps1 -ShowToast

# Live test with Software Center data
.\Invoke-ToastFromSoftwareCenter.ps1 -TestMode

# Check logs
Get-Content "C:\ProgramData\ToastNotification\Logs\SoftwareCenterToast.log"

# Reset duplicate tracking
Remove-Item "$env:APPDATA\ToastNotificationScript\ShownToasts.json" -Force

# Trigger scheduled task manually
Get-ScheduledTask -TaskName "ToastNotification-SoftwareCenter" | Start-ScheduledTask

# Clean up everything
cd "<path-to-repo>\TestEnvironment"
.\Remove-POCEnvironment.ps1
```
