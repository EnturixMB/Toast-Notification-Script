# Concept: Software Center Description-Driven Toast Notifications

## Overview

This concept describes how to extend the Toast Notification Script so that toast notifications can be **configured directly from the Description field** of Software Center deployments (SCCM/MEMCM). Instead of managing separate XML config files, administrators embed hashtag-based configuration tags into the deployment description text. A lightweight PowerShell script, deployed as a **Scheduled Task triggered at user logon**, queries all available Software Center deployments, parses their descriptions for configuration tags, and triggers toast notifications accordingly.

---

## Motivation

- **Centralized control**: Administrators manage toast behavior directly where they manage deployments — inside the Configuration Manager console.
- **No separate config hosting**: Eliminates the need to host XML files on web servers or file shares.
- **Per-deployment granularity**: Each Software Center deployment can carry its own toast configuration, so different applications or updates get different notifications.
- **Simple rollout**: A single scheduled task deployed once to all clients handles everything.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  SCCM / MEMCM Console                       │
│                                                             │
│  Deployment: "7-Zip 24.09"                                  │
│  Description:                                               │
│    #toast                                                   │
│    #Headline=New Software Available                         │
│    #Description=7-Zip 24.09 is now available. Please        │
│    install it from Software Center.                         │
│    #Deadline=2026-03-15                                     │
│    #ActionButton=Open Software Center                       │
│    #Action=softwarecenter:Page=Applications                 │
│    #HeroImage=https://corp.example.com/images/7zip.png      │
│                                                             │
└────────────────────────────┬────────────────────────────────┘
                             │  Deployments are delivered
                             │  to clients via SCCM agent
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                     Client Device                            │
│                                                             │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Scheduled Task (Logon Trigger)                        │  │
│  │  Runs: Invoke-ToastFromSoftwareCenter.ps1              │  │
│  │  Context: Current User                                 │  │
│  └────────────┬───────────────────────────────────────────┘  │
│               │                                              │
│               ▼                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Step 1: Query Software Center                         │  │
│  │  WMI: CCM_Application / CCM_Program                    │  │
│  │  → Get all Available deployments                       │  │
│  │  → Read the Description field of each                  │  │
│  └────────────┬───────────────────────────────────────────┘  │
│               │                                              │
│               ▼                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Step 2: Parse Description for #toast tag              │  │
│  │  → If #toast is present → continue                     │  │
│  │  → If #toast is absent  → skip this deployment         │  │
│  └────────────┬───────────────────────────────────────────┘  │
│               │                                              │
│               ▼                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Step 3: Extract configuration tags                    │  │
│  │  → #Headline, #Description, #Deadline, etc.            │  │
│  │  → Map to existing Toast XML config fields             │  │
│  └────────────┬───────────────────────────────────────────┘  │
│               │                                              │
│               ▼                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Step 4: Generate in-memory XML configuration          │  │
│  │  → Build <Configuration> XML matching existing format  │  │
│  │  → Merge with base/default template                    │  │
│  └────────────┬───────────────────────────────────────────┘  │
│               │                                              │
│               ▼                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Step 5: Invoke Remediate-ToastNotification.ps1        │  │
│  │  → Pass generated XML config                           │  │
│  │  → Display toast notification to user                  │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Tag Syntax

Tags are placed in the **Description** field of a Software Center deployment. Each tag starts with `#` and uses `=` to assign a value. Tags can appear on separate lines or on the same line.

### Trigger Tag (Required)

| Tag | Purpose | Example |
|-----|---------|---------|
| `#toast` | **Activates** toast processing for this deployment. Without this tag, the deployment is ignored. | `#toast` |

### Content Tags (Optional — override defaults)

| Tag | Maps to XML Field | Purpose | Example |
|-----|-------------------|---------|---------|
| `#Headline=<text>` | `HeaderText` | The small header line at the top of the toast | `#Headline=IT Department Notice` |
| `#Title=<text>` | `TitleText` | The bold title text of the toast notification | `#Title=New Software Available` |
| `#Description=<text>` | `BodyText1` | The primary body text of the toast | `#Description=7-Zip 24.09 is ready to install.` |
| `#Body2=<text>` | `BodyText2` | The secondary body text (additional detail) | `#Body2=Please install at your earliest convenience.` |
| `#Attribution=<text>` | `AttributionText` | Small text at the bottom of the toast | `#Attribution=IT Helpdesk` |

### Scheduling Tags (Optional)

| Tag | Maps to XML Field | Purpose | Example |
|-----|-------------------|---------|---------|
| `#Deadline=<date>` | *(new concept)* | Show toast only until this date (ISO 8601). After the deadline passes, the toast is no longer displayed. | `#Deadline=2026-03-15` |
| `#StartDate=<date>` | *(new concept)* | Show toast only from this date onward | `#StartDate=2026-03-01` |

### Appearance Tags (Optional)

| Tag | Maps to XML Field | Purpose | Example |
|-----|-------------------|---------|---------|
| `#HeroImage=<url>` | `HeroImageName` | URL to the hero image shown at the top of the toast | `#HeroImage=https://corp.example.com/hero.png` |
| `#LogoImage=<url>` | `LogoImageName` | URL to the logo/icon image | `#LogoImage=https://corp.example.com/logo.png` |
| `#Scenario=<type>` | `Scenario` | Toast behavior: `reminder`, `short`, `long`, or `alarm` | `#Scenario=reminder` |

### Action Tags (Optional)

| Tag | Maps to XML Field | Purpose | Example |
|-----|-------------------|---------|---------|
| `#ActionButton=<text>` | `ActionButton1` text | Label for the primary action button | `#ActionButton=Install Now` |
| `#Action=<protocol>` | `Action1` | Protocol/URL launched when the action button is clicked | `#Action=softwarecenter:Page=Applications` |
| `#ActionButton2=<text>` | `ActionButton2` text | Label for a secondary action button | `#ActionButton2=Learn More` |
| `#Action2=<url>` | `Action2` | Protocol/URL for the second button | `#Action2=https://wiki.corp.com/7zip` |
| `#DismissButton=<text>` | `DismissButton` text | Label for the dismiss button | `#DismissButton=Later` |

---

## Tag-to-XML Mapping

The following table shows exactly how each parsed tag maps to the existing `<Configuration>` XML format used by `Remediate-ToastNotification.ps1`.

```
Description Tag          →   XML Element / Attribute
─────────────────────────────────────────────────────────────
#toast                   →   <Feature Name="Toast" Enabled="True" />
#Headline=<value>        →   <Text Name="HeaderText">value</Text>
#Title=<value>           →   <Text Name="TitleText">value</Text>
#Description=<value>     →   <Text Name="BodyText1">value</Text>
#Body2=<value>           →   <Text Name="BodyText2">value</Text>
#Attribution=<value>     →   <Text Name="AttributionText">value</Text>
#Deadline=<value>        →   (New) Used for date-range filtering logic
#StartDate=<value>       →   (New) Used for date-range filtering logic
#HeroImage=<value>       →   <Option Name="HeroImageName" Value="value" />
#LogoImage=<value>       →   <Option Name="LogoImageName" Value="value" />
#Scenario=<value>        →   <Option Name="Scenario" Type="value" />
#ActionButton=<value>    →   <Option Name="ActionButton1" Enabled="True" />
                             <Text Name="ActionButton1">value</Text>
#Action=<value>          →   <Option Name="Action1" Value="value" />
#ActionButton2=<value>   →   <Option Name="ActionButton2" Enabled="True" />
                             <Text Name="ActionButton2">value</Text>
#Action2=<value>         →   <Option Name="Action2" Value="value" />
#DismissButton=<value>   →   <Option Name="DismissButton" Enabled="True" />
                             <Text Name="DismissButton">value</Text>
```

Any tags not specified in the description fall back to values from a **base template** XML (a default config bundled with the script or hosted at a URL).

---

## Example: Software Center Description

### What the admin types in the SCCM Console (Deployment Description field):

```
This deployment installs 7-Zip 24.09 for all users.

#toast
#Headline=IT Department
#Title=New Software Available: 7-Zip 24.09
#Description=A new version of 7-Zip has been published to Software Center. Please install it at your earliest convenience.
#Body2=This update includes important security fixes.
#Deadline=2026-03-15
#ActionButton=Open Software Center
#Action=softwarecenter:Page=Applications
#DismissButton=Remind me later
#Scenario=reminder
#HeroImage=https://corp.example.com/images/software-update-hero.png
```

### What the user sees:

A Windows toast notification with:
- **Header**: "IT Department"
- **Title**: "Good morning, John — New Software Available: 7-Zip 24.09"
- **Body**: "A new version of 7-Zip has been published to Software Center..."
- **Secondary text**: "This update includes important security fixes."
- **Buttons**: [Open Software Center] [Remind me later]
- **Hero image**: Custom banner from corporate URL

### The generated in-memory XML (produced by the script):

```xml
<?xml version="1.0" encoding="utf-8"?>
<Configuration>
    <Feature Name="Toast" Enabled="True" />
    <Feature Name="PendingRebootUptime" Enabled="False" />
    <Feature Name="WeeklyMessage" Enabled="False" />
    <Option Name="CustomNotificationApp" Enabled="True" Value="IT NOTIFICATIONS" />
    <Option Name="LogoImageName" Value="https://toast.imab.dk/ToastLogoImageIMAB.png" />
    <Option Name="HeroImageName" Value="https://corp.example.com/images/software-update-hero.png" />
    <Option Name="ActionButton1" Enabled="True" />
    <Option Name="ActionButton2" Enabled="False" />
    <Option Name="DismissButton" Enabled="True" />
    <Option Name="SnoozeButton" Enabled="False" />
    <Option Name="Scenario" Type="reminder" />
    <Option Name="Action1" Value="softwarecenter:Page=Applications" />
    <Option Name="Action2" Value="" />
    <en-US>
        <Text Name="HeaderText">IT Department</Text>
        <Text Name="TitleText">New Software Available: 7-Zip 24.09</Text>
        <Text Name="BodyText1">A new version of 7-Zip has been published to Software Center. Please install it at your earliest convenience.</Text>
        <Text Name="BodyText2">This update includes important security fixes.</Text>
        <Text Name="ActionButton1">Open Software Center</Text>
        <Text Name="DismissButton">Remind me later</Text>
        <Text Name="AttributionText">www.imab.dk</Text>
        <!-- ... remaining text fields from base template ... -->
    </en-US>
</Configuration>
```

---

## Minimal Example

The simplest possible description to trigger a toast with all defaults:

```
#toast
```

This triggers a toast on every logon using the base template defaults for all text, images, and buttons.

A slightly more useful minimal example:

```
#toast
#Title=Please install the latest update
#Description=A critical security update is available in Software Center.
```

---

## Deployment Model

### Scheduled Task (Logon Trigger)

The solution is deployed as a **Scheduled Task** to all clients. This can be done via:
- Group Policy Preferences (GPP)
- SCCM Task Sequence / Baseline
- PowerShell script deployed via SCCM

#### Scheduled Task Configuration:

| Setting | Value |
|---------|-------|
| **Name** | `ToastNotification-SoftwareCenter` |
| **Trigger** | At logon (any user) |
| **Action** | `powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramData\ToastNotification\Invoke-ToastFromSoftwareCenter.ps1"` |
| **Run as** | Current logged-on user (not SYSTEM) |
| **Conditions** | Run only when user is logged on |
| **Settings** | Allow task to be run on demand; stop if running longer than 5 minutes |

#### Files deployed to each client:

```
C:\ProgramData\ToastNotification\
├── Invoke-ToastFromSoftwareCenter.ps1   ← New: Orchestrator script
├── Remediate-ToastNotification.ps1      ← Existing: Toast display engine
├── config-toast-base-template.xml       ← Base template with defaults
└── Logs\
    └── SoftwareCenterToast.log          ← Runtime log
```

---

## Processing Flow (Step-by-Step)

### Step 1 — Query Available Deployments

Use the SCCM client WMI namespace to enumerate all deployments visible in Software Center:

```
WMI Namespace:  root\ccm\ClientSDK
WMI Class:      CCM_Application          (for Applications)
                CCM_Program              (for Packages/Programs)

Key Properties:
  - Name                                 → Deployment display name
  - Description                          → The field we parse for tags
  - InstallState / ResolvedState         → Filter for "Available" state
  - Deadline                             → Native SCCM deadline (optional fallback)
```

### Step 2 — Filter for #toast

For each deployment returned:
1. Read the `Description` property
2. Check if it contains the string `#toast` (case-insensitive)
3. If `#toast` is **not** found → skip this deployment
4. If `#toast` **is** found → proceed to parse tags

### Step 3 — Parse Configuration Tags

Use regex to extract all `#TagName=Value` pairs from the description text:

```
Pattern:  #(\w+)(?:=(.+?))?(?=\s*#|\s*$)
```

This captures:
- `#toast` (tag with no value)
- `#Headline=Some text here` (tag with value)

### Step 4 — Apply Date Filtering

If `#Deadline` is present:
- Parse the date value
- If today's date is **after** the deadline → skip this deployment (no toast)

If `#StartDate` is present:
- Parse the date value
- If today's date is **before** the start date → skip this deployment (no toast)

### Step 5 — Duplicate Prevention

To avoid showing the same toast on every logon:
- Maintain a small tracking file: `%APPDATA%\ToastNotificationScript\ShownToasts.json`
- Store a hash of each deployment's `Name + Description` with a timestamp
- On each logon, check if the toast for this deployment was already shown
- Re-show a toast if the description has changed (hash mismatch) or a configurable interval has passed

### Step 6 — Generate XML Configuration

- Load the base template XML
- Override specific fields with values from parsed tags (see Tag-to-XML Mapping above)
- The result is a complete in-memory `[xml]` object compatible with `Remediate-ToastNotification.ps1`

### Step 7 — Display Toast

- Call the existing toast display logic from `Remediate-ToastNotification.ps1`
- The existing script handles: custom app registration, image downloads, greeting personalization, and WinRT notification display
- Log success/failure per deployment

---

## Multiple Deployments

If multiple Software Center deployments contain `#toast`, **each one generates its own toast notification**. The script processes them sequentially with a short delay between notifications to avoid overwhelming the user.

Recommended behavior:
- Process a maximum of **3 toast notifications per logon** (configurable)
- Prioritize deployments with the nearest `#Deadline`
- Log skipped deployments for admin review

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| No SCCM client installed | Log warning, exit gracefully (exit code 0) |
| No deployments found | Log info, exit gracefully |
| No deployments with `#toast` | Log info, exit gracefully |
| Invalid tag value (e.g., bad date) | Log warning, skip that tag, use default |
| WMI query fails | Log error, exit with error code |
| Toast display fails | Log error per deployment, continue to next |

---

## Security Considerations

- The script runs in **user context** (not SYSTEM), consistent with the existing toast script requirement
- WMI queries to `root\ccm\ClientSDK` are read-only
- No credentials are stored or transmitted
- Description text is treated as untrusted input: all parsed values are sanitized before being inserted into XML
- Image URLs are validated (HTTPS only recommended) before download
- The scheduled task executable path should be protected with appropriate NTFS permissions (`C:\ProgramData\ToastNotification\` — admin-writable, user-readable)

---

## Future Extensions

Once the basic `#toast` concept is proven, additional tags could be added:

| Tag | Purpose |
|-----|---------|
| `#SnoozeButton=<text>` | Enable snooze with custom button text |
| `#Snooze` | Enable snooze with default text |
| `#Priority=high` | Use `alarm` scenario for critical deployments |
| `#Language=da-DK` | Force a specific language for the toast |
| `#RepeatDays=3` | Re-show the toast every N days until deadline |
| `#RequireAction` | Don't allow dismiss; user must click an action button |
| `#DeadlineFromSCCM` | Use the native SCCM deployment deadline instead of a manual date |

---

## Summary

| Aspect | Detail |
|--------|--------|
| **Trigger** | Scheduled Task at user logon |
| **Data Source** | Software Center deployment Description field (WMI) |
| **Activation** | `#toast` tag in description |
| **Configuration** | Hashtag-based: `#Headline=`, `#Title=`, `#Description=`, `#Deadline=`, etc. |
| **Toast Engine** | Existing `Remediate-ToastNotification.ps1` (no changes needed to core script) |
| **Config Format** | Tags are parsed and mapped to the existing XML `<Configuration>` format in-memory |
| **Deployment** | One-time deployment of scheduled task + script files to all clients |
| **Duplicate Prevention** | Hash-based tracking in `%APPDATA%` per user |
| **Multiple Toasts** | Each `#toast`-tagged deployment generates its own notification (max 3 per logon) |
