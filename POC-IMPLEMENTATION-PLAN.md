# POC Implementation Plan: Software Center Description-Driven Toast Notifications

> **Based on:** [CONCEPT-SoftwareCenter-ToastIntegration.md](CONCEPT-SoftwareCenter-ToastIntegration.md)
> **Type:** Proof of Concept — No production hardening, no full error handling
> **Language:** PowerShell 5.1 (Windows built-in)
> **Scope:** Single MECM-managed client, single deployment, German (de-DE) user-facing text

---

## Overview

This plan breaks the concept into **9 sequential implementation steps**, each with a clear deliverable and an **AI Agent Prompt** that can be used to implement that step. The steps are ordered by dependency — each step builds on the previous one.

### POC Goals

1. Parse a `[TOAST-BEGIN]`…`[TOAST-END]` block from a Software Center deployment description
2. Resolve short-form aliases to full tag names
3. Generate an in-memory XML configuration compatible with `Remediate-ToastNotification.ps1`
4. Display a toast notification to the user using the existing toast engine
5. Auto-suppress toasts for already-installed software
6. Prevent duplicate toasts via hash-based tracking

### POC Non-Goals (Deferred to Post-POC)

- Fuzzy-match logging for unrecognized tags
- `StartDate` / `Deadline` date-range filtering
- Multiple deployment handling (max 3 cap, prioritization)
- Scheduled task deployment automation (GPP / SCCM baseline)
- Image pre-staging automation
- `-TestMode` switch
- Production-grade error handling and logging

---

## File Structure (Target State After POC)

```
C:\ProgramData\ToastNotification\
├── Invoke-ToastFromSoftwareCenter.ps1    ← NEW: Orchestrator script (POC deliverable)
├── Remediate-ToastNotification.ps1       ← EXISTING: Toast display engine (unchanged)
├── config-toast-base-template.xml        ← NEW: German base template with defaults
├── Images\
│   ├── hero-info.png                     ← NEW: Info level hero image (placeholder)
│   ├── logo-info.png                     ← NEW: Info level logo image (placeholder)
│   ├── hero-warnung.png                  ← NEW: Warning level hero image (placeholder)
│   ├── logo-warnung.png                  ← NEW: Warning level logo image (placeholder)
│   ├── hero-kritisch.png                 ← NEW: Critical level hero image (placeholder)
│   └── logo-kritisch.png                 ← NEW: Critical level logo image (placeholder)
└── Logs\
    └── SoftwareCenterToast.log           ← NEW: Runtime log (auto-created)
```

---

## Step 1: Create the German Base Template XML

### Deliverable
A `config-toast-base-template.xml` file that contains all default values for the German (de-DE) toast configuration, matching the XML format expected by `Remediate-ToastNotification.ps1`.

### Key Requirements
- Feature `Toast` enabled, all other features disabled
- Default buttons: `ActionButton1` = "Software Center öffnen" (enabled), `DismissButton` = "Schließen" (enabled)
- Default action: `Action1` = `softwarecenter:Page=Applications`
- `ActionButton2` and `SnoozeButton` disabled
- `Scenario` type = `short`
- `CustomNotificationApp` enabled with value `IT NOTIFICATIONS`
- Image paths point to local pre-staged images: `C:\ProgramData\ToastNotification\Images\logo-info.png` and `hero-info.png` (info is the default urgency)
- `<de-DE>` language block with all required text fields:
  - `HeaderText` empty (will be set dynamically or from tag)
  - `TitleText` empty (will be set from tag)
  - `BodyText1` empty (will be set from tag)
  - `BodyText2` empty (optional, from tag)
  - `ActionButton1` = "Software Center öffnen"
  - `DismissButton` = "Schließen"
  - `AttributionText` empty (optional, from tag)
  - `GreetMorningText` = "Guten Morgen"
  - `GreetAfternoonText` = "Guten Tag"
  - `GreetEveningText` = "Guten Abend"
- Multi-language support disabled (single language: German)

### AI Agent Prompt

```
You are working in the Toast Notification Script repository at /home/runner/work/Toast-Notification-Script/Toast-Notification-Script.

Create a new file called `config-toast-base-template.xml` in the repository root.

This file is a German (de-DE) base template XML configuration for `Remediate-ToastNotification.ps1`.
Use the exact same XML structure as the existing `config-toast-pendingreboot.xml` file in this
repository, but with these specific values:

Features:
- Toast: Enabled="True"
- PendingRebootUptime: Enabled="False"
- WeeklyMessage: Enabled="False"

Options:
- MaxUptimeDays: Value="-6" (inherited from existing configs — means 6 days; the negative sign is the convention used by the existing Remediate script's uptime comparison logic)
- WeeklyMessageDay: Value="4"
- WeeklyMessageHour: Value="-1"
- PendingRebootUptimeText: Enabled="False"
- CustomNotificationApp: Enabled="True" Value="IT NOTIFICATIONS"
- LogoImageName: Value="C:\ProgramData\ToastNotification\Images\logo-info.png"
- HeroImageName: Value="C:\ProgramData\ToastNotification\Images\hero-info.png"
- ActionButton1: Enabled="True"
- ActionButton2: Enabled="False"
- DismissButton: Enabled="True"
- SnoozeButton: Enabled="False"
- Scenario: Type="short"
- Action1: Value="softwarecenter:Page=Applications"
- Action2: Value=""

Text block:
- MultiLanguageSupport: Enabled="False"
- Use a <de-DE> block (not en-US) with German text
- HeaderText: empty (leave blank)
- TitleText: empty (leave blank)
- BodyText1: empty (leave blank)
- BodyText2: empty (leave blank)
- AttributionText: empty (leave blank)
- ActionButton1: "Software Center öffnen"
- ActionButton2: empty
- DismissButton: "Schließen"
- SnoozeButton: "Später erinnern"
- GreetMorningText: "Guten Morgen"
- GreetAfternoonText: "Guten Tag"
- GreetEveningText: "Guten Abend"
- PendingRebootUptimeText: empty
- WeeklyMessageTitle: empty
- WeeklyMessageBody: empty

Make sure the XML is well-formed, UTF-8 encoded, and follows the exact same element ordering as
the existing config files in this repository.
```

---

## Step 2: Create Placeholder Urgency-Based Images

### Deliverable
Six placeholder PNG images in the `Images/` directory, organized by urgency level (info, warnung, kritisch). These are simple colored placeholders for POC purposes.

### Key Requirements
- 3 urgency levels × 2 images (hero + logo) = 6 files
- File naming convention: `hero-{level}.png` and `logo-{level}.png`
- Hero images: approximately 364×180 px (standard toast hero size)
- Logo images: approximately 48×48 px (standard toast logo size)
- Color coding: info = blue/green, warnung = yellow/orange, kritisch = red
- Simple solid-color or gradient images are sufficient for POC

### AI Agent Prompt

```
You are working in the Toast Notification Script repository at /home/runner/work/Toast-Notification-Script/Toast-Notification-Script.

Create 6 placeholder PNG images in the `Images/` directory for 3 urgency levels. These are POC
placeholders — simple colored rectangles are sufficient. Use PowerShell or Python to generate them.

Files to create:
1. Images/hero-info.png      — 364x180 px, blue (#0078D4) background, white text "INFO"
2. Images/logo-info.png      — 48x48 px, blue (#0078D4) background, white text "i"
3. Images/hero-warnung.png   — 364x180 px, orange (#FF8C00) background, white text "WARNUNG"
4. Images/logo-warnung.png   — 48x48 px, orange (#FF8C00) background, white text "!"
5. Images/hero-kritisch.png  — 364x180 px, red (#D13438) background, white text "KRITISCH"
6. Images/logo-kritisch.png  — 48x48 px, red (#D13438) background, white text "!!"

Use any available image generation method (e.g., Python Pillow library, or PowerShell
System.Drawing). The images only need to be valid PNGs with the correct dimensions and colors.
Text overlay is optional — solid color blocks are acceptable for the POC.
```

---

## Step 3: Build the `[TOAST-BEGIN]` Block Parser Function

### Deliverable
A PowerShell function `Get-ToastBlockFromDescription` that extracts and parses the `[TOAST-BEGIN]`…`[TOAST-END]` block from a deployment description string.

### Key Requirements
- Input: a string (the deployment description text)
- Output: a hashtable of parsed key-value pairs with aliases resolved to full names
- Case-insensitive search for `[TOAST-BEGIN]` and `[TOAST-END]` markers
- Use `ConvertFrom-StringData` for parsing (no regex for key=value extraction)
- Resolve short-form aliases using the mapping table from the concept:
  - `h` → `Headline`, `t` → `Title`, `d` → `Description`, `b2` → `Body2`
  - `at` → `Attribution`, `dl` → `Deadline`, `sd` → `StartDate`
  - `hi` → `HeroImage`, `li` → `LogoImage`, `u` → `Urgency`, `sc` → `Scenario`
  - `ab` → `ActionButton`, `a` → `Action`, `ab2` → `ActionButton2`, `a2` → `Action2`, `db` → `DismissButton`
- Return `$null` if no `[TOAST-BEGIN]` marker is found
- Ignore all text outside the markers
- Log warnings for unrecognized keys (simple Write-Warning for POC)

### AI Agent Prompt

```
You are working in the Toast Notification Script repository at /home/runner/work/Toast-Notification-Script/Toast-Notification-Script.

Create a PowerShell function called `Get-ToastBlockFromDescription` to be included in the new
`Invoke-ToastFromSoftwareCenter.ps1` script. Do NOT create the full script yet — just the function.
Write it to a temporary file for now: `/tmp/toast-poc/Get-ToastBlockFromDescription.ps1`

Function signature:
  function Get-ToastBlockFromDescription {
      param([string]$Description)
  }

Behavior:
1. Search $Description for '[TOAST-BEGIN]' (case-insensitive)
2. If not found, return $null
3. If found, extract everything between '[TOAST-BEGIN]' and '[TOAST-END]'
4. Use ConvertFrom-StringData to parse the extracted block into key-value pairs
   - Note: ConvertFrom-StringData expects `Key=Value` per line, which matches our format
   - Handle edge cases: empty lines, whitespace-only lines (filter them out before parsing)
5. Resolve short-form aliases to full tag names using this mapping:
   h=Headline, t=Title, d=Description, b2=Body2, at=Attribution,
   dl=Deadline, sd=StartDate, hi=HeroImage, li=LogoImage, u=Urgency,
   sc=Scenario, ab=ActionButton, a=Action, ab2=ActionButton2, a2=Action2, db=DismissButton
6. Return the resolved hashtable

Use the existing coding conventions from Remediate-ToastNotification.ps1:
- Use CIM cmdlets (not WMI)
- Use Write-Warning for warnings
- Follow existing variable naming style

Include a comment block at the top of the function explaining its purpose.

Test the function with these sample inputs:
- A description with a full [TOAST-BEGIN]...[TOAST-END] block using short aliases
- A description with no toast block (should return $null)
- A description with full tag names (no aliases)
```

---

## Step 4: Build the XML Configuration Generator Function

### Deliverable
A PowerShell function `New-ToastXmlFromTags` that takes the parsed tag hashtable and the base template XML, and produces a complete in-memory `[xml]` configuration object.

### Key Requirements
- Input: hashtable of parsed tags (from Step 3), path to base template XML
- Output: `[xml]` object compatible with `Remediate-ToastNotification.ps1`
- Load the base template XML from `config-toast-base-template.xml`
- Apply tag-to-XML mapping as defined in the concept:
  - `Headline` → `<Text Name="HeaderText">`
  - `Title` → `<Text Name="TitleText">`
  - `Description` → `<Text Name="BodyText1">`
  - `Body2` → `<Text Name="BodyText2">`
  - `Attribution` → `<Text Name="AttributionText">`
  - `HeroImage` → `<Option Name="HeroImageName" Value="...">`
  - `LogoImage` → `<Option Name="LogoImageName" Value="...">`
  - `Scenario` → `<Option Name="Scenario" Type="...">`
  - `ActionButton` → `<Text Name="ActionButton1">` + ensure `<Option Name="ActionButton1" Enabled="True">`
  - `Action` → `<Option Name="Action1" Value="...">`
  - `ActionButton2` → `<Text Name="ActionButton2">` + set `<Option Name="ActionButton2" Enabled="True">`
  - `Action2` → `<Option Name="Action2" Value="...">`
  - `DismissButton` → `<Text Name="DismissButton">`
- Handle `Urgency` tag by mapping to local image paths:
  - `info` (default) → `hero-info.png` / `logo-info.png`
  - `warnung` → `hero-warnung.png` / `logo-warnung.png`
  - `kritisch` → `hero-kritisch.png` / `logo-kritisch.png`
  - Unknown value → fall back to `info`, log a warning
- All image paths prefixed with `C:\ProgramData\ToastNotification\Images\`
- Unspecified tags retain base template defaults

### AI Agent Prompt

```
You are working in the Toast Notification Script repository at /home/runner/work/Toast-Notification-Script/Toast-Notification-Script.

Create a PowerShell function called `New-ToastXmlFromTags` to be included in the new
`Invoke-ToastFromSoftwareCenter.ps1` script. Write it to: `/tmp/toast-poc/New-ToastXmlFromTags.ps1`

Function signature:
  function New-ToastXmlFromTags {
      param(
          [hashtable]$Tags,
          [string]$BaseTemplatePath
      )
  }

This function reads the base XML template from $BaseTemplatePath (config-toast-base-template.xml)
and overlays values from the $Tags hashtable onto it.

Behavior:
1. Load the base template XML: [xml]$xml = Get-Content -Path $BaseTemplatePath -Encoding UTF8
2. Determine the language node — use 'de-DE' (the only language block in the template)
3. For each tag in $Tags, apply the tag-to-XML mapping:

   Tag Name        → XML Target
   ──────────────────────────────────────────────────────────────────
   Headline        → Set inner text of <Text Name="HeaderText"> in <de-DE>
   Title           → Set inner text of <Text Name="TitleText"> in <de-DE>
   Description     → Set inner text of <Text Name="BodyText1"> in <de-DE>
   Body2           → Set inner text of <Text Name="BodyText2"> in <de-DE>
   Attribution     → Set inner text of <Text Name="AttributionText"> in <de-DE>
   HeroImage       → Set Value attribute of <Option Name="HeroImageName">
   LogoImage       → Set Value attribute of <Option Name="LogoImageName">
   Scenario        → Set Type attribute of <Option Name="Scenario">
   ActionButton    → Set inner text of <Text Name="ActionButton1"> in <de-DE>
                     Ensure <Option Name="ActionButton1" Enabled="True">
   Action          → Set Value attribute of <Option Name="Action1">
   ActionButton2   → Set inner text of <Text Name="ActionButton2"> in <de-DE>
                     Set <Option Name="ActionButton2" Enabled="True">
   Action2         → Set Value attribute of <Option Name="Action2">
   DismissButton   → Set inner text of <Text Name="DismissButton"> in <de-DE>

4. Handle Urgency tag specially:
   - If $Tags contains 'Urgency', map it to image paths:
     'info'     → hero-info.png / logo-info.png
     'warnung'  → hero-warnung.png / logo-warnung.png
     'kritisch' → hero-kritisch.png / logo-kritisch.png
   - Prefix all image filenames with: C:\ProgramData\ToastNotification\Images\
   - If Urgency value is unrecognized, fall back to 'info' and Write-Warning
   - Set both HeroImageName and LogoImageName Option values in the XML
   - Note: explicit HeroImage/LogoImage tags override the Urgency-based defaults

5. Return the modified [xml] object

Use XPath or PowerShell XML node access to find and modify the correct elements.
Reference the existing config XML files in the repository for the exact element structure.
Use the coding conventions from Remediate-ToastNotification.ps1 (CIM over WMI, Write-Warning, etc.)

Test the function by:
- Loading config-toast-base-template.xml (created in Step 1)
- Passing a hashtable with Title, Description, and Urgency=warnung
- Verifying the output XML has the correct values set
```

---

## Step 5: Build the WMI Query Function for Software Center Deployments

### Deliverable
A PowerShell function `Get-SoftwareCenterDeployments` that queries the SCCM client WMI namespace for all available deployments and returns their name, description, and installation state.

### Key Requirements
- Query `root\ccm\ClientSDK` namespace
- Query both `CCM_Application` and `CCM_Program` classes
- Return objects with properties: `Name`, `Description`, `InstallState`, `Type` (Application/Program)
- Use `Get-CimInstance` (not `Get-WmiObject`) per codebase conventions
- Handle gracefully: no SCCM client installed, no deployments found
- Filter out deployments where software is already installed (`InstallState -eq "Installed"`)

### AI Agent Prompt

```
You are working in the Toast Notification Script repository at /home/runner/work/Toast-Notification-Script/Toast-Notification-Script.

Create a PowerShell function called `Get-SoftwareCenterDeployments` to be included in the new
`Invoke-ToastFromSoftwareCenter.ps1` script. Write it to: `/tmp/toast-poc/Get-SoftwareCenterDeployments.ps1`

Function signature:
  function Get-SoftwareCenterDeployments {
      param()
  }

This function queries the SCCM/MECM client WMI namespace for available Software Center deployments.

Behavior:
1. Check if the SCCM client WMI namespace exists:
   - Try: Get-CimInstance -Namespace 'root\ccm\ClientSDK' -ClassName 'CCM_Application' -ErrorAction Stop
   - If it fails, log a warning and return $null

2. Query CCM_Application class for applications:
   - Namespace: root\ccm\ClientSDK
   - Select: Name, Description, InstallState
   - Use Get-CimInstance (NOT Get-WmiObject — this is a codebase convention)

3. Query CCM_Program class for packages/programs (if applicable):
   - Namespace: root\ccm\ClientSDK
   - Select: Name, Description, ResolvedState (equivalent of InstallState for programs)

4. Combine results into a unified list of PSCustomObjects with properties:
   - Name: deployment display name
   - Description: the description field (where [TOAST-BEGIN] block may be)
   - IsInstalled: $true if InstallState = "Installed" (Applications) or equivalent for Programs
   - Type: "Application" or "Program"

5. Filter OUT deployments where IsInstalled = $true (auto-suppress)
   - Log: "INFO: Deployment '<Name>' already installed — toast suppressed."

6. Return the filtered list of deployments (only those NOT yet installed)

Reference the existing `Get-AvailableDeploymentFields.ps1` in this repository for the correct
WMI namespace, class names, and property names. Use Get-CimInstance consistently.

Important: This function cannot be tested without an actual SCCM client. Include a comment
block explaining how to test it, and include a mock/test helper example that returns fake
deployment data for local development.
```

---

## Step 6: Build the Duplicate Prevention Function

### Deliverable
A PowerShell function `Test-ToastAlreadyShown` and a companion `Set-ToastShown` that manage a JSON tracking file to prevent showing the same toast on every logon/unlock.

### Key Requirements
- Tracking file location: `$env:APPDATA\ToastNotificationScript\ShownToasts.json`
- Store a hash of `Name + Description` for each shown toast, plus a timestamp
- `Test-ToastAlreadyShown`: returns `$true` if the toast hash already exists in the tracking file
- `Set-ToastShown`: adds or updates the hash entry after a toast is shown
- Re-show a toast if the description has changed (hash mismatch)
- Create the tracking directory and file if they don't exist
- Use `Get-FileHash` or `[System.Security.Cryptography.SHA256]` for hashing

### AI Agent Prompt

```
You are working in the Toast Notification Script repository at /home/runner/work/Toast-Notification-Script/Toast-Notification-Script.

Create two PowerShell functions for duplicate toast prevention. Write them to:
`/tmp/toast-poc/ToastDuplicatePrevention.ps1`

Function 1: Test-ToastAlreadyShown
  param(
      [string]$DeploymentName,
      [string]$Description
  )

  Behavior:
  1. Compute a SHA256 hash of ($DeploymentName + $Description)
  2. Read the tracking file: $env:APPDATA\ToastNotificationScript\ShownToasts.json
     - If the file doesn't exist, return $false (toast was never shown)
  3. Check if the hash exists in the JSON data
  4. If hash exists → return $true (toast was already shown)
  5. If hash does NOT exist → return $false (toast is new or description changed)

Function 2: Set-ToastShown
  param(
      [string]$DeploymentName,
      [string]$Description
  )

  Behavior:
  1. Compute the same SHA256 hash of ($DeploymentName + $Description)
  2. Read the existing tracking file (or create empty structure if missing)
  3. Add or update the entry: { hash: "<hash>", name: "<name>", timestamp: "<ISO8601>" }
  4. Write the updated JSON back to the tracking file
  5. Create the directory $env:APPDATA\ToastNotificationScript\ if it doesn't exist

Use PowerShell's ConvertTo-Json / ConvertFrom-Json for JSON handling.
Use [System.Security.Cryptography.SHA256]::Create() for hashing.
Follow the coding conventions from Remediate-ToastNotification.ps1 in this repository.

Test both functions locally by:
- Calling Set-ToastShown with a test deployment name and description
- Verifying the JSON file was created
- Calling Test-ToastAlreadyShown with the same inputs (should return $true)
- Calling Test-ToastAlreadyShown with a different description (should return $false)
```

---

## Step 7: Assemble the Orchestrator Script

### Deliverable
The main `Invoke-ToastFromSoftwareCenter.ps1` script that ties all functions together into a single orchestrator.

### Key Requirements
- Combine all functions from Steps 3–6 into one script
- Main execution flow (matches concept Steps 1–8):
  1. Query Software Center deployments (Step 5 function)
  2. For each deployment:
     a. Check if already installed → skip (auto-suppress)
     b. Parse description for `[TOAST-BEGIN]` block (Step 3 function)
     c. If no block found → skip
     d. Check duplicate tracking (Step 6 function) → skip if already shown
     e. Generate in-memory XML config (Step 4 function)
     f. Save XML to a temp file and invoke `Remediate-ToastNotification.ps1` with `-Config` parameter
     g. Record toast as shown (Step 6 function)
- Simple file-based logging to `C:\ProgramData\ToastNotification\Logs\SoftwareCenterToast.log`
- Process a maximum of 3 toasts per run
- Graceful exit (exit code 0) for all non-error conditions

### AI Agent Prompt

```
You are working in the Toast Notification Script repository at /home/runner/work/Toast-Notification-Script/Toast-Notification-Script.

Create the main orchestrator script: `Invoke-ToastFromSoftwareCenter.ps1` in the repository root.

This script is the entry point that will be executed by the scheduled task. It ties together all
the individual functions into a single flow.

Script structure:
1. Script header with CmdletBinding and parameters:
   - No mandatory parameters
   - Optional: [switch]$TestMode (skips duplicate prevention for rapid testing)

2. Configuration variables at the top:
   - $BasePath = "C:\ProgramData\ToastNotification"
   - $BaseTemplatePath = Join-Path $BasePath "config-toast-base-template.xml"
   - $RemediateScriptPath = Join-Path $BasePath "Remediate-ToastNotification.ps1"
   - $LogPath = Join-Path $BasePath "Logs\SoftwareCenterToast.log"
   - $MaxToastsPerRun = 3

3. Simple logging function: Write-ToastLog
   - Appends timestamped messages to $LogPath
   - Creates the Logs directory if it doesn't exist
   - Also writes to console via Write-Output

4. Include all functions inline (not dot-sourced, for simplicity):
   - Get-ToastBlockFromDescription (from Step 3)
   - New-ToastXmlFromTags (from Step 4)
   - Get-SoftwareCenterDeployments (from Step 5)
   - Test-ToastAlreadyShown (from Step 6)
   - Set-ToastShown (from Step 6)

5. Main execution flow:
   a. Log: "Starting Software Center toast notification check..."
   b. Call Get-SoftwareCenterDeployments
      - If $null or empty → log "No uninstalled deployments found." → exit 0
   c. Initialize $toastCount = 0
   d. ForEach deployment in the results:
      - If $toastCount -ge $MaxToastsPerRun → log "Max toasts reached." → break
      - Call Get-ToastBlockFromDescription with the deployment's Description
        - If $null → log "No [TOAST-BEGIN] block in '<Name>'." → continue
      - If NOT $TestMode:
        - Call Test-ToastAlreadyShown with Name and Description
          - If $true → log "Toast already shown for '<Name>'." → continue
      - Call New-ToastXmlFromTags with parsed tags and $BaseTemplatePath
      - Save the XML to a temp file: $tempConfig = Join-Path $env:TEMP "toast-config-$(Get-Random).xml"
        - $xml.Save($tempConfig)
      - Invoke the toast engine:
        powershell.exe -ExecutionPolicy Bypass -File $RemediateScriptPath -Config $tempConfig
      - Call Set-ToastShown with Name and Description
      - Remove the temp config file
      - Increment $toastCount
      - Log: "Toast displayed for '<Name>'."
   e. Log: "Completed. $toastCount toast(s) displayed."
   f. Exit 0

Use the coding conventions from Remediate-ToastNotification.ps1:
- CIM cmdlets (not WMI)
- Write-Warning for warnings
- Consistent variable naming
- Comment blocks for each function

Reference the existing Remediate-ToastNotification.ps1 to understand how it accepts the -Config
parameter (it accepts a file path or URL, and loads it with Get-Content -Encoding UTF8).
```

---

## Step 8: Create the Scheduled Task Configuration

### Deliverable
A PowerShell script or documentation that registers the scheduled task on a client machine with both logon and workstation unlock triggers.

### Key Requirements
- Task name: `ToastNotification-SoftwareCenter`
- Trigger 1: At logon (any user)
- Trigger 2: On workstation unlock (SessionUnlock via `SessionStateChangeTrigger`, or Event ID `4801`)
- Action: `powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramData\ToastNotification\Invoke-ToastFromSoftwareCenter.ps1"`
- Run as: current logged-on user (not SYSTEM)
- Run only when user is logged on
- Stop if running longer than 5 minutes
- Allow task to be run on demand

### AI Agent Prompt

```
You are working in the Toast Notification Script repository at /home/runner/work/Toast-Notification-Script/Toast-Notification-Script.

Create a PowerShell script called `Register-ToastScheduledTask.ps1` in the repository root.

This script registers a Windows Scheduled Task that triggers the toast orchestrator on logon
and workstation unlock.

Requirements:
1. Task Name: "ToastNotification-SoftwareCenter"
2. Two triggers:
   a. AtLogon trigger (any user)
   b. SessionUnlock trigger (SessionStateChangeTrigger with StateChange = SessionUnlock)
      - Alternative: Event log trigger on Microsoft-Windows-Security-Auditing, Event ID 4801
3. Action:
   - Execute: powershell.exe
   - Arguments: -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramData\ToastNotification\Invoke-ToastFromSoftwareCenter.ps1"
4. Principal: run as the current logged-on user (GroupId "BUILTIN\Users"), RunLevel = Limited
5. Settings:
   - RunOnlyIfLoggedOn = $true
   - AllowDemandStart = $true
   - ExecutionTimeLimit = PT5M (5 minutes)
   - DisallowStartIfOnBatteries = $false
   - StopIfGoingOnBatteries = $false
6. Use Register-ScheduledTask cmdlet
7. If a task with the same name already exists, unregister it first and re-register

Include comments explaining each section. Add a -Unregister switch to remove the task.

Note: This script is meant to be run as Administrator (elevated) since it registers a
scheduled task. Add a check at the top to verify admin privileges.
```

---

## Step 9: End-to-End POC Validation

### Deliverable
A validation script and checklist to verify the complete POC flow works end-to-end on an MECM-managed client.

### Key Requirements
- Validate each component individually before testing the full flow
- Test with a real Software Center deployment that has a `[TOAST-BEGIN]` block in its description
- Verify auto-suppress behavior by installing the software and re-running
- Verify duplicate prevention by running twice without installing
- Verify the unlock trigger works (lock → unlock → toast appears)
- Document expected vs. actual results

### AI Agent Prompt

```
You are working in the Toast Notification Script repository at /home/runner/work/Toast-Notification-Script/Toast-Notification-Script.

Create a PowerShell script called `Test-ToastPOC.ps1` in the repository root.

This is a validation script for testing the POC without a live SCCM environment. It simulates
the full flow using mock data.

The script should:

1. Simulate deployment data (bypass WMI):
   Create an array of fake deployment objects with:
   a. A deployment WITH a [TOAST-BEGIN] block (not installed):
      Name = "7-Zip 24.09"
      Description = "Dieses Deployment installiert 7-Zip 24.09.\n\n[TOAST-BEGIN]\nt=Neue Software verfügbar\nd=7-Zip 24.09 steht bereit.\nu=warnung\n[TOAST-END]"
      IsInstalled = $false
   b. A deployment WITHOUT a [TOAST-BEGIN] block:
      Name = "Notepad++ 8.6"
      Description = "Standard text editor installation."
      IsInstalled = $false
   c. A deployment WITH a [TOAST-BEGIN] block but already installed:
      Name = "VLC Media Player"
      Description = "[TOAST-BEGIN]\nt=VLC verfügbar\nd=Bitte installieren.\n[TOAST-END]"
      IsInstalled = $true

2. Run through the orchestrator logic step by step:
   - For each deployment, print what action would be taken
   - Show the parsed tags
   - Show the generated XML (pretty-printed)
   - Indicate whether the toast would be shown or suppressed (and why)

3. Output a summary:
   - Total deployments found: X
   - Deployments with [TOAST-BEGIN] block: X
   - Toasts suppressed (already installed): X
   - Toasts suppressed (duplicate): X
   - Toasts displayed: X

4. Optionally (if -ShowToast switch is provided):
   - Actually invoke Remediate-ToastNotification.ps1 with the generated XML
   - This requires the script and images to be in place at C:\ProgramData\ToastNotification\

Include Write-Host output with colors for pass/fail/skip status for each deployment.
This script serves as both a test harness and a demonstration of the full flow.
```

---

## Implementation Order & Dependencies

```
Step 1: Base Template XML ──────────────────────────────────────┐
                                                                │
Step 2: Placeholder Images ─────────────────────────────────────┤
                                                                │
Step 3: Block Parser Function ──────────────┐                   │
                                            │                   │
Step 4: XML Generator Function ─────────────┤ (depends on 1,3) │
                                            │                   │
Step 5: WMI Query Function ─────────────────┤                   │
                                            │                   │
Step 6: Duplicate Prevention ───────────────┤                   │
                                            │                   │
Step 7: Orchestrator Script ────────────────┘ (depends on 3-6)  │
                                                                │
Step 8: Scheduled Task Registration ────────────────────────────┘
                                                                │
Step 9: End-to-End POC Validation ──────────────────────────────┘ (depends on all)
```

### Parallelizable Steps

- **Steps 1 and 2** can be done in parallel (no dependencies)
- **Steps 3, 5, and 6** can be done in parallel (independent functions)
- **Step 4** depends on Step 1 (base template) and Step 3 (parser output format)
- **Step 7** depends on Steps 3–6 (all functions)
- **Step 8** has no code dependencies but requires Step 7 for the script path
- **Step 9** depends on all previous steps

---

## POC Validation Checklist

- [ ] Base template XML loads correctly in PowerShell (`[xml](Get-Content ...)`)
- [ ] Placeholder images exist and are valid PNGs
- [ ] `Get-ToastBlockFromDescription` correctly parses a block with short aliases
- [ ] `Get-ToastBlockFromDescription` returns `$null` for descriptions without a block
- [ ] `New-ToastXmlFromTags` produces valid XML with correct values
- [ ] `New-ToastXmlFromTags` correctly applies urgency-based image paths
- [ ] `Get-SoftwareCenterDeployments` handles missing SCCM client gracefully
- [ ] `Test-ToastAlreadyShown` returns `$false` for new toasts
- [ ] `Test-ToastAlreadyShown` returns `$true` for previously shown toasts
- [ ] `Set-ToastShown` creates the tracking JSON file correctly
- [ ] Orchestrator script processes mock deployments correctly
- [ ] Orchestrator script respects the max 3 toasts per run cap
- [ ] Scheduled task registers successfully with both triggers
- [ ] End-to-end: toast appears on logon with mock data
- [ ] End-to-end: toast is suppressed after marking as installed
- [ ] End-to-end: toast is suppressed on second run (duplicate prevention)

---

## Post-POC Enhancements (Out of Scope)

These items are explicitly deferred to after the POC is validated:

| Enhancement | Description |
|-------------|-------------|
| Fuzzy-match tag suggestions | Log `WARNING: Unknown tag 'Headlne' — did you mean 'Headline'?` |
| Date-range filtering | Implement `Deadline` and `StartDate` tag processing |
| Multi-deployment prioritization | Sort by nearest deadline, cap at 3, queue remainder |
| Production logging | Structured logging with levels (INFO/WARN/ERROR) |
| GPP deployment template | Group Policy Preferences XML for scheduled task rollout |
| Image pre-staging automation | SCCM package to deploy the 6 urgency images to clients |
| `-TestMode` enhancements | Extend TestMode to also bypass auto-suppress and add verbose diagnostics |
| Configurable repeat interval | Re-show toast after N days even if previously shown |
| Error reporting | Centralized reporting of toast display success/failure |
