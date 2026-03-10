# Concept: Software Center Description-Driven Toast Notifications

## Overview

This concept describes how to extend the Toast Notification Script so that toast notifications can be **configured directly from the Description field** of Software Center deployments (SCCM/MEMCM). Instead of managing separate XML config files, administrators embed a structured `[TOAST-BEGIN]`…`[TOAST-END]` block into the deployment description text. A lightweight PowerShell script, deployed as a **Scheduled Task triggered at user logon**, queries all available Software Center deployments, parses their descriptions for the toast block, and triggers toast notifications accordingly.

### Core Principles

- **No `#toast` anchor needed** — Only the `[TOAST-BEGIN]`…`[TOAST-END]` block matters. If the block is present, a toast is triggered.
- **Default buttons always present** — Every toast automatically includes "Software Center öffnen" and "Schließen" as default buttons, without needing to specify them.
- **3 urgency-based default image sets** — Three image sets (Info, Warnung, Kritisch) are pre-staged locally on the client. Selected via the `Urgency` tag.
- **Minimal configuration** — All parameters are unset by default. Only explicitly specified parameters in the `[TOAST-BEGIN]` block override defaults.
- **Auto-suppress on install** — Once the software has been successfully installed, the toast notification is automatically suppressed.
- **German toast content** — All default text shown to end users (button labels, greeting, attribution) is in German.

---

## Motivation

- **Centralized control**: Administrators manage toast behavior directly where they manage deployments — inside the Configuration Manager console.
- **No separate config hosting**: Eliminates the need to host XML files on web servers or file shares.
- **Per-deployment granularity**: Each Software Center deployment can carry its own toast configuration, so different applications or updates get different notifications.
- **Simple rollout**: A single scheduled task deployed once to all clients handles everything.
- **Auto-suppress on install**: Once the software is successfully installed, the notification is automatically suppressed — no manual cleanup needed.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  SCCM / MEMCM Console                       │
│                                                             │
│  Deployment: "7-Zip 24.09"                                  │
│  Description:                                               │
│    Dieses Deployment installiert 7-Zip 24.09.               │
│                                                             │
│    [TOAST-BEGIN]                                             │
│    t=Neue Software verfügbar                                │
│    d=7-Zip 24.09 steht bereit. Bitte installieren.          │
│    [TOAST-END]                                              │
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
│  │  Step 2: Check Installation State                      │  │
│  │  → Query InstallState / ResolvedState via WMI          │  │
│  │  → If already installed → suppress toast, skip         │  │
│  └────────────┬───────────────────────────────────────────┘  │
│               │                                              │
│               ▼                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Step 3: Detect [TOAST-BEGIN]…[TOAST-END] block        │  │
│  │  → Scan description for [TOAST-BEGIN] marker           │  │
│  │  → If not found → skip deployment (no toast)           │  │
│  │  → Extract block between markers                       │  │
│  └────────────┬───────────────────────────────────────────┘  │
│               │                                              │
│               ▼                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Step 4: Parse Key=Value pairs                         │  │
│  │  → ConvertFrom-StringData (no regex needed)            │  │
│  │  → Resolve short-form aliases (h→Headline, t→Title…)   │  │
│  │  → Log warnings for unrecognized keys (fuzzy-match)    │  │
│  └────────────┬───────────────────────────────────────────┘  │
│               │                                              │
│               ▼                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Step 5: Generate in-memory XML configuration          │  │
│  │  → Build <Configuration> XML matching existing format  │  │
│  │  → Merge with base/default template                    │  │
│  │  → Select images based on Urgency level                │  │
│  │  → Default buttons: Software Center öffnen + Schließen │  │
│  └────────────┬───────────────────────────────────────────┘  │
│               │                                              │
│               ▼                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Step 6: Invoke Remediate-ToastNotification.ps1        │  │
│  │  → Pass generated XML config                           │  │
│  │  → Display toast notification to user                  │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Tag Syntax

Toast configuration is embedded in the **Description** field of a Software Center deployment. The human-readable description stays at the top; the toast config lives below a clearly delimited block and can be visually ignored by end users even if they happen to scroll down.

### Delimited Block Convention

The toast configuration **must** be placed inside a fenced block marked by `[TOAST-BEGIN]` and `[TOAST-END]` markers in the description field. Everything outside the markers is treated as regular description text and is never parsed. Within the block, each line is a simple `Key=Value` pair parsed with PowerShell's built-in `ConvertFrom-StringData` — no regex needed.

**No `#toast` anchor is needed.** The presence of `[TOAST-BEGIN]` alone is sufficient to trigger toast processing.

```
Beschreibungstext für Endbenutzer.
Dieser Teil wird im Software Center angezeigt.

[TOAST-BEGIN]
t=Neue Software verfügbar
d=Bitte installieren Sie das neueste Update.
[TOAST-END]
```

### Lean on Defaults

All parameters are **unset by default** except for the following built-in defaults that are always present:

| Default | Value | Notes |
|---------|-------|-------|
| **ActionButton1** | `Software Center öffnen` | Opens Software Center Applications page |
| **Action1** | `softwarecenter:Page=Applications` | Protocol link |
| **DismissButton** | `Schließen` | Dismiss the notification |
| **Urgency** | `info` | Selects the Info image set (blue/green) |
| **Images** | Local pre-staged files based on urgency | See [Urgency-Based Default Images](#urgency-based-default-images) |

Administrators should specify **only the tags that differ** from these defaults. In practice, most toasts need only `Title` and `Description` — well within any character limit.

### Auto-Suppress on Successful Installation

Before displaying a toast, the script checks the **installation state** of the associated deployment via WMI (`InstallState` / `ResolvedState` from `CCM_Application` or `CCM_Program`). If the software is already marked as **installed**, the toast is automatically suppressed. This means:

- No notification is shown for software the user has already installed
- No manual cleanup or deadline management is needed for completed deployments
- The `[TOAST-BEGIN]` block can remain in the description permanently — it only produces toasts while the software is not yet installed

### Urgency-Based Default Images

Three sets of default images are pre-staged locally on every client under `C:\ProgramData\ToastNotification\Images\`. Each set contains a Hero image and a Logo image, styled for a different urgency level:

| Urgency Level | Tag Value | Hero Image | Logo Image | Visual Style |
|---------------|-----------|------------|------------|--------------|
| **Info** (default) | `info` | `hero-info.png` | `logo-info.png` | Blue/green, neutral — for general announcements |
| **Warning** | `warnung` | `hero-warnung.png` | `logo-warnung.png` | Yellow/orange — for important updates |
| **Critical** | `kritisch` | `hero-kritisch.png` | `logo-kritisch.png` | Red — for urgent/security-critical updates |

The urgency level is selected via the `Urgency` tag (alias `u`). If not specified, `info` is used as the default.

Example:
```
[TOAST-BEGIN]
t=Kritisches Sicherheitsupdate
d=Ein kritisches Sicherheitsupdate steht bereit. Bitte sofort installieren.
u=kritisch
[TOAST-END]
```

### Content Tags (Optional — override defaults)

| Tag | Short Alias | Maps to XML Field | Purpose | Example |
|-----|-------------|-------------------|---------|---------|
| `Headline=<text>` | `h=<text>` | `HeaderText` | The small header line at the top of the toast | `Headline=IT-Abteilung` |
| `Title=<text>` | `t=<text>` | `TitleText` | The bold title text of the toast notification | `Title=Neue Software verfügbar` |
| `Description=<text>` | `d=<text>` | `BodyText1` | The primary body text of the toast | `Description=7-Zip 24.09 steht zur Installation bereit.` |
| `Body2=<text>` | `b2=<text>` | `BodyText2` | The secondary body text (additional detail) | `Body2=Bitte installieren Sie die Software zeitnah.` |
| `Attribution=<text>` | `at=<text>` | `AttributionText` | Small text at the bottom of the toast | `Attribution=IT-Helpdesk` |

### Scheduling Tags (Optional)

| Tag | Short Alias | Maps to XML Field | Purpose | Example |
|-----|-------------|-------------------|---------|---------|
| `Deadline=<date>` | `dl=<date>` | *(new concept)* | Show toast only until this date (ISO 8601). After the deadline passes, the toast is no longer displayed. | `Deadline=2026-03-15` |
| `StartDate=<date>` | `sd=<date>` | *(new concept)* | Show toast only from this date onward | `StartDate=2026-03-01` |

### Appearance Tags (Optional)

| Tag | Short Alias | Maps to XML Field | Purpose | Example |
|-----|-------------|-------------------|---------|---------|
| `HeroImage=<url>` | `hi=<url>` | `HeroImageName` | URL to the hero image shown at the top of the toast. **Not needed in most cases** — default images are selected by urgency level. | `HeroImage=https://corp.example.com/hero.png` |
| `LogoImage=<url>` | `li=<url>` | `LogoImageName` | URL to the logo/icon image. **Not needed in most cases** — default images are selected by urgency level. | `LogoImage=https://corp.example.com/logo.png` |
| `Urgency=<level>` | `u=<level>` | *(new concept)* | Selects the pre-staged image set: `info` (default), `warnung`, or `kritisch` | `Urgency=warnung` |
| `Scenario=<type>` | `sc=<type>` | `Scenario` | Toast behavior: `reminder`, `short`, `long`, or `alarm` | `Scenario=reminder` |

### Action Tags (Optional — defaults are pre-configured)

The default buttons "Software Center öffnen" and "Schließen" are **always present** without any configuration. Use these tags only to **override** the default button labels or actions.

| Tag | Short Alias | Maps to XML Field | Purpose | Default | Example |
|-----|-------------|-------------------|---------|---------|---------|
| `ActionButton=<text>` | `ab=<text>` | `ActionButton1` text | Label for the primary action button | `Software Center öffnen` | `ActionButton=Jetzt installieren` |
| `Action=<protocol>` | `a=<protocol>` | `Action1` | Protocol/URL launched when the action button is clicked | `softwarecenter:Page=Applications` | `Action=softwarecenter:Page=Updates` |
| `ActionButton2=<text>` | `ab2=<text>` | `ActionButton2` text | Label for a secondary action button | *(not set)* | `ActionButton2=Mehr erfahren` |
| `Action2=<url>` | `a2=<url>` | `Action2` | Protocol/URL for the second button | *(not set)* | `Action2=https://wiki.corp.com/7zip` |
| `DismissButton=<text>` | `db=<text>` | `DismissButton` text | Label for the dismiss button | `Schließen` | `DismissButton=Später erinnern` |

### Short-Form Alias Mapping Table

To reduce character overhead by 50–70%, compact aliases can be used in place of full tag names inside the `[TOAST-BEGIN]`…`[TOAST-END]` block. The client-side script converts them internally before processing.

| Short Alias | Full Tag Name |
|-------------|---------------|
| `h` | `Headline` |
| `t` | `Title` |
| `d` | `Description` |
| `b2` | `Body2` |
| `at` | `Attribution` |
| `dl` | `Deadline` |
| `sd` | `StartDate` |
| `hi` | `HeroImage` |
| `li` | `LogoImage` |
| `u` | `Urgency` |
| `sc` | `Scenario` |
| `ab` | `ActionButton` |
| `a` | `Action` |
| `ab2` | `ActionButton2` |
| `a2` | `Action2` |
| `db` | `DismissButton` |

---

## Tag-to-XML Mapping

The following table shows exactly how each parsed `Key=Value` line (from the `[TOAST-BEGIN]`…`[TOAST-END]` block) maps to the existing `<Configuration>` XML format used by `Remediate-ToastNotification.ps1`. Short-form aliases are resolved to their full tag name before this mapping is applied.

```
Key (or Short Alias)     →   XML Element / Attribute
─────────────────────────────────────────────────────────────
Headline (h)             →   <Text Name="HeaderText">value</Text>
Title (t)                →   <Text Name="TitleText">value</Text>
Description (d)          →   <Text Name="BodyText1">value</Text>
Body2 (b2)               →   <Text Name="BodyText2">value</Text>
Attribution (at)         →   <Text Name="AttributionText">value</Text>
Deadline (dl)            →   (New) Used for date-range filtering logic
StartDate (sd)           →   (New) Used for date-range filtering logic
HeroImage (hi)           →   <Option Name="HeroImageName" Value="value" />
LogoImage (li)           →   <Option Name="LogoImageName" Value="value" />
Urgency (u)              →   (New) Selects pre-staged image set; maps to HeroImageName + LogoImageName
Scenario (sc)            →   <Option Name="Scenario" Type="value" />
ActionButton (ab)        →   <Option Name="ActionButton1" Enabled="True" />
                             <Text Name="ActionButton1">value</Text>
Action (a)               →   <Option Name="Action1" Value="value" />
ActionButton2 (ab2)      →   <Option Name="ActionButton2" Enabled="True" />
                             <Text Name="ActionButton2">value</Text>
Action2 (a2)             →   <Option Name="Action2" Value="value" />
DismissButton (db)       →   <Option Name="DismissButton" Enabled="True" />
                             <Text Name="DismissButton">value</Text>
```

Any keys not specified in the delimited block fall back to the built-in defaults:
- **ActionButton1**: `Software Center öffnen` → opens `softwarecenter:Page=Applications`
- **DismissButton**: `Schließen`
- **Images**: Selected by `Urgency` level (default: `info`) from locally pre-staged files
- All other parameters remain unset unless explicitly specified

---

## Example: Software Center Description

### What the admin types in the SCCM Console (Deployment Description field):

```
Dieses Deployment installiert 7-Zip 24.09 für alle Benutzer.
Bitte installieren Sie es über das Software Center.

[TOAST-BEGIN]
Headline=IT-Abteilung
Title=Neue Software verfügbar: 7-Zip 24.09
Description=Eine neue Version von 7-Zip wurde im Software Center veröffentlicht. Bitte installieren Sie diese zeitnah.
Body2=Dieses Update enthält wichtige Sicherheitskorrekturen.
Deadline=2026-03-15
Urgency=warnung
[TOAST-END]
```

> **Note:** No `#toast` anchor is needed. The parser simply scans each deployment description for the `[TOAST-BEGIN]` marker. If found, it extracts and parses the structured block between `[TOAST-BEGIN]` and `[TOAST-END]` using `ConvertFrom-StringData`. The human-readable text above the block is never parsed. The buttons "Software Center öffnen" and "Schließen" are automatically included as defaults.

### The same example using short-form aliases (saves ~50% characters):

```
Dieses Deployment installiert 7-Zip 24.09 für alle Benutzer.

[TOAST-BEGIN]
h=IT-Abteilung
t=Neue Software verfügbar: 7-Zip 24.09
d=Eine neue Version von 7-Zip wurde im Software Center veröffentlicht. Bitte installieren Sie diese zeitnah.
b2=Dieses Update enthält wichtige Sicherheitskorrekturen.
dl=2026-03-15
u=warnung
[TOAST-END]
```

### What the user sees:

A Windows toast notification with:
- **Header**: "IT-Abteilung"
- **Title**: "Guten Morgen, Max — Neue Software verfügbar: 7-Zip 24.09"
- **Body**: "Eine neue Version von 7-Zip wurde im Software Center veröffentlicht..."
- **Secondary text**: "Dieses Update enthält wichtige Sicherheitskorrekturen."
- **Buttons**: [Software Center öffnen] [Schließen]
- **Hero image**: Pre-staged warning-level banner (`hero-warnung.png`)
- **Logo image**: Pre-staged warning-level logo (`logo-warnung.png`)

> **Note:** Once 7-Zip 24.09 is installed successfully, this toast is automatically suppressed. The `[TOAST-BEGIN]` block can remain in the description permanently — it will simply stop producing toasts.

### The generated in-memory XML (produced by the script):

```xml
<?xml version="1.0" encoding="utf-8"?>
<Configuration>
    <Feature Name="Toast" Enabled="True" />
    <Feature Name="PendingRebootUptime" Enabled="False" />
    <Feature Name="WeeklyMessage" Enabled="False" />
    <Option Name="CustomNotificationApp" Enabled="True" Value="IT NOTIFICATIONS" />
    <Option Name="LogoImageName" Value="C:\ProgramData\ToastNotification\Images\logo-warnung.png" />
    <Option Name="HeroImageName" Value="C:\ProgramData\ToastNotification\Images\hero-warnung.png" />
    <Option Name="ActionButton1" Enabled="True" />
    <Option Name="ActionButton2" Enabled="False" />
    <Option Name="DismissButton" Enabled="True" />
    <Option Name="SnoozeButton" Enabled="False" />
    <Option Name="Scenario" Type="short" />
    <Option Name="Action1" Value="softwarecenter:Page=Applications" />
    <Option Name="Action2" Value="" />
    <de-DE>
        <Text Name="HeaderText">IT-Abteilung</Text>
        <Text Name="TitleText">Neue Software verfügbar: 7-Zip 24.09</Text>
        <Text Name="BodyText1">Eine neue Version von 7-Zip wurde im Software Center veröffentlicht. Bitte installieren Sie diese zeitnah.</Text>
        <Text Name="BodyText2">Dieses Update enthält wichtige Sicherheitskorrekturen.</Text>
        <Text Name="ActionButton1">Software Center öffnen</Text>
        <Text Name="DismissButton">Schließen</Text>
        <Text Name="AttributionText">IT-Abteilung</Text>
        <Text Name="GreetMorningText">Guten Morgen</Text>
        <Text Name="GreetAfternoonText">Guten Tag</Text>
        <Text Name="GreetEveningText">Guten Abend</Text>
        <!-- ... remaining text fields from base template ... -->
    </de-DE>
</Configuration>
```

> **Note:** `LogoImageName` and `HeroImageName` default to the `warnung` image set because `Urgency=warnung` was specified. The default buttons "Software Center öffnen" and "Schließen" are included automatically.

---

## Minimal Example

The simplest possible description to trigger a toast with all defaults:

```
[TOAST-BEGIN]
t=Neue Software verfügbar
d=Bitte installieren Sie das neueste Update über das Software Center.
[TOAST-END]
```

Only two keys (`t` and `d`) are specified. Everything else — headline, images (Info level), buttons ("Software Center öffnen" / "Schließen"), scenario — uses the built-in defaults. This keeps the description field clean and well within character limits.

> **Note:** Once the software is installed, this toast is automatically suppressed.

### Three urgency examples side by side:

**Info (default — no urgency tag needed):**
```
[TOAST-BEGIN]
t=Neue optionale Software
d=Eine neue Version von Notepad++ ist verfügbar.
[TOAST-END]
```

**Warning:**
```
[TOAST-BEGIN]
t=Wichtiges Update verfügbar
d=Bitte installieren Sie das Update zeitnah.
u=warnung
[TOAST-END]
```

**Critical:**
```
[TOAST-BEGIN]
t=Kritisches Sicherheitsupdate
d=Ein kritisches Sicherheitsupdate muss sofort installiert werden.
u=kritisch
[TOAST-END]
```

---

## Deployment Model

### Scheduled Task (Logon + Unlock Trigger)

The solution is deployed as a **Scheduled Task** to all clients with **two triggers**: user logon and workstation unlock. This can be done via:
- Group Policy Preferences (GPP)
- SCCM Task Sequence / Baseline
- PowerShell script deployed via SCCM

#### Scheduled Task Configuration:

| Setting | Value |
|---------|-------|
| **Name** | `ToastNotification-SoftwareCenter` |
| **Trigger 1** | At logon (any user) |
| **Trigger 2** | On workstation unlock (Event Log: `Microsoft-Windows-Security-Auditing`, Event ID `4801`) |
| **Action** | `powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramData\ToastNotification\Invoke-ToastFromSoftwareCenter.ps1"` |
| **Run as** | Current logged-on user (not SYSTEM) |
| **Conditions** | Run only when user is logged on |
| **Settings** | Allow task to be run on demand; stop if running longer than 5 minutes |

> **Note:** The workstation unlock trigger ensures users see pending notifications even after returning from a break or locking their PC. Combined with auto-suppress on install, this means: if the user installs the software and then locks/unlocks, no toast will appear. The unlock trigger uses Windows Security Event ID `4801` (workstation unlocked). Alternatively, a `SessionUnlock` trigger can be configured via the `SessionStateChangeTrigger` in Task Scheduler (SessionType `7` = SessionUnlock).

#### Files deployed to each client:

```
C:\ProgramData\ToastNotification\
├── Invoke-ToastFromSoftwareCenter.ps1   ← New: Orchestrator script
├── Remediate-ToastNotification.ps1      ← Existing: Toast display engine
├── config-toast-base-template.xml       ← Base template with defaults (German)
├── Images\
│   ├── hero-info.png                    ← Info level hero image (blue/green)
│   ├── logo-info.png                    ← Info level logo image
│   ├── hero-warnung.png                 ← Warning level hero image (yellow/orange)
│   ├── logo-warnung.png                 ← Warning level logo image
│   ├── hero-kritisch.png                ← Critical level hero image (red)
│   └── logo-kritisch.png               ← Critical level logo image
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
  - Description                          → The field we parse for the [TOAST-BEGIN] block
  - InstallState / ResolvedState         → Used to check if already installed (auto-suppress)
  - Deadline                             → Native SCCM deadline (optional fallback)
```

### Step 2 — Check Installation State (Auto-Suppress)

Before parsing the description, check whether the software is already installed:

1. Read `InstallState` (for `CCM_Application`) or `ResolvedState` (for `CCM_Program`)
2. If the state indicates **installed** (e.g., `InstallState = "Installed"`) → **skip this deployment entirely**
3. Log: `INFO: Deployment '7-Zip 24.09' already installed — toast suppressed.`
4. If **not installed** → proceed to Step 3

This ensures that:
- Users never see notifications for software they have already installed
- The `[TOAST-BEGIN]` block can remain in the description permanently
- No manual cleanup or deadline management is needed for completed deployments

### Step 3 — Detect [TOAST-BEGIN] Block

Scan the deployment description for the `[TOAST-BEGIN]` marker:

1. Read the `Description` property of each deployment
2. Search for `[TOAST-BEGIN]` (case-insensitive)
3. If `[TOAST-BEGIN]` is **not** found → skip this deployment (no toast configured)
4. If `[TOAST-BEGIN]` **is** found → proceed to Step 4

Everything outside the `[TOAST-BEGIN]`…`[TOAST-END]` markers is treated as plain human-readable text and is **ignored entirely**.

### Step 4 — Extract and Parse Configuration

Extract and parse the structured block:

1. Extract the text between `[TOAST-BEGIN]` and `[TOAST-END]`
2. Parse the extracted block using PowerShell's built-in `ConvertFrom-StringData` — **no regex needed**
3. Resolve short-form aliases (e.g., `h` → `Headline`, `t` → `Title`, `u` → `Urgency`) using the alias mapping table
4. Map resolved keys to their corresponding XML fields (see Tag-to-XML Mapping)
5. Log warnings for unrecognized keys with fuzzy-match suggestions

### Step 5 — Apply Date Filtering

If `Deadline` is present in the parsed keys:
- Parse the date value
- If today's date is **after** the deadline → skip this deployment (no toast)

If `StartDate` is present in the parsed keys:
- Parse the date value
- If today's date is **before** the start date → skip this deployment (no toast)

### Step 6 — Duplicate Prevention

To avoid showing the same toast on every logon or unlock:
- Maintain a small tracking file: `%APPDATA%\ToastNotificationScript\ShownToasts.json`
- Store a hash of each deployment's `Name + Description` with a timestamp
- On each logon or unlock, check if the toast for this deployment was already shown
- Re-show a toast if the description has changed (hash mismatch) or a configurable interval has passed

### Step 7 — Generate XML Configuration

- Load the base template XML (German defaults)
- Apply built-in defaults: ActionButton1 = "Software Center öffnen", DismissButton = "Schließen"
- Select images based on `Urgency` level (default: `info`)
- Override specific fields with values from parsed tags (see Tag-to-XML Mapping above)
- The result is a complete in-memory `[xml]` object compatible with `Remediate-ToastNotification.ps1`

### Step 8 — Display Toast

- Call the existing toast display logic from `Remediate-ToastNotification.ps1`
- The existing script handles: custom app registration, image display, greeting personalization, and WinRT notification display
- Log success/failure per deployment
- Log any unrecognized keys as warnings with fuzzy-match suggestions (see Error Handling)

---

## Multiple Deployments

If multiple Software Center deployments contain a `[TOAST-BEGIN]` block, **each one generates its own toast notification** (provided the software is not already installed). The script processes them sequentially with a short delay between notifications to avoid overwhelming the user.

Recommended behavior:
- Process a maximum of **3 toast notifications per logon/unlock** (configurable)
- Prioritize deployments with the nearest `Deadline`
- Skip deployments where the software is already installed (auto-suppress)
- Log skipped deployments for admin review

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| No SCCM client installed | Log warning, exit gracefully (exit code 0) |
| No deployments found | Log info, exit gracefully |
| No deployments with `[TOAST-BEGIN]` block | Log info, exit gracefully |
| Software already installed | Log info, suppress toast (auto-suppress) |
| Invalid tag value (e.g., bad date) | Log warning, skip that tag, use default |
| Unrecognized key in `[TOAST-BEGIN]` block | Log warning with fuzzy-match suggestion (see below) |
| Unknown `Urgency` value | Log warning, fall back to `info` image set |
| WMI query fails | Log error, exit with error code |
| Toast display fails | Log error per deployment, continue to next |

### Fuzzy-Match Logging for Unrecognized Tags

When the client-side script encounters an unrecognized key inside the `[TOAST-BEGIN]`…`[TOAST-END]` block, it logs a prominent warning with a fuzzy-match suggestion to accelerate troubleshooting. For example:

```
WARNING: Unknown tag 'Headlne' in deployment '7-Zip 24.09' — did you mean 'Headline' (alias: 'h')?
WARNING: Unknown tag 'Tilte' in deployment '7-Zip 24.09' — did you mean 'Title' (alias: 't')?
WARNING: Unknown tag 'BodyText' in deployment '7-Zip 24.09' — did you mean 'Body2' (alias: 'b2')?
```

The fuzzy-match algorithm compares the unrecognized key against all known full tag names and short aliases, suggesting the closest match. This allows administrators to:
- **Review centralized logs** to identify misconfigurations across the estate
- **Run the script in test mode** on a single machine to validate a new deployment's toast configuration before broad rollout
- Quickly identify and fix typos without needing to inspect the description field directly

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

Once the basic concept is proven, additional tags could be added:

| Tag | Purpose |
|-----|---------|
| `SnoozeButton=<text>` | Enable snooze with custom button text |
| `Snooze` | Enable snooze with default text ("Später erinnern") |
| `Priority=high` | Use `alarm` scenario for critical deployments |
| `RepeatDays=3` | Re-show the toast every N days until deadline |
| `RequireAction` | Don't allow dismiss; user must click an action button |
| `DeadlineFromSCCM` | Use the native SCCM deployment deadline instead of a manual date |

---

## Summary

| Aspect | Detail |
|--------|--------|
| **Trigger** | Scheduled Task at user logon and workstation unlock |
| **Data Source** | Software Center deployment Description field (WMI) |
| **Activation** | `[TOAST-BEGIN]`…`[TOAST-END]` block in description (no `#toast` anchor needed) |
| **Configuration** | Structured `Key=Value` lines inside the block; supports short-form aliases |
| **Parsing** | Single-pass: scan for `[TOAST-BEGIN]` marker, extract block, parse with `ConvertFrom-StringData`, resolve aliases |
| **Auto-Suppress** | Toast automatically suppressed when software is already installed (WMI `InstallState` check) |
| **Toast Engine** | Existing `Remediate-ToastNotification.ps1` (no changes needed to core script) |
| **Config Format** | Keys are parsed, aliases resolved, and mapped to the existing XML `<Configuration>` format in-memory |
| **Default Buttons** | "Software Center öffnen" + "Schließen" — always present without configuration |
| **Default Images** | 3 urgency-based image sets (Info/Warnung/Kritisch) pre-staged locally on client |
| **Defaults** | All other parameters unset unless explicitly specified; only `Title` and `Description` are typically needed |
| **Language** | All user-facing toast text in German (de-DE) |
| **Deployment** | One-time deployment of scheduled task + script files + 3 image sets to all clients |
| **Duplicate Prevention** | Hash-based tracking in `%APPDATA%` per user |
| **Multiple Toasts** | Each deployment with a `[TOAST-BEGIN]` block generates its own notification (max 3 per trigger, auto-suppress on install) |
| **Error Feedback** | Unrecognized keys logged as warnings with fuzzy-match suggestions |

---

## POC Simplification Suggestions

The following recommendations make the proof-of-concept as simple and fast to implement as possible:

### 1. Start with a Single Deployment

For the initial POC, configure just **one** Software Center deployment with a `[TOAST-BEGIN]` block. Validate the full flow end-to-end before adding more deployments.

### 2. Use Only `Title` and `Description`

The minimal configuration is just two lines. Don't configure buttons, images, scenario, or scheduling for the first test — all defaults handle it:

```
[TOAST-BEGIN]
t=Test-Benachrichtigung
d=Dies ist ein Test der Toast-Benachrichtigungen.
[TOAST-END]
```

### 3. Pre-Stage Images Once, Forget About Them

Deploy all 6 image files (3 urgency levels × 2 images each) to the client once. After that, the `Urgency` tag (or the default `info` level) handles image selection automatically — no URLs needed.

### 4. Skip Scheduling Tags for POC

Don't set `Deadline` or `StartDate` during the POC. The auto-suppress on install is the primary lifecycle mechanism — toasts disappear automatically once the software is installed.

### 5. Test with the Unlock Trigger

The workstation unlock trigger is the fastest way to iterate during POC testing: lock the PC, unlock it, and see if the toast appears. No need to log off and on again.

### 6. Use a Tracking-Free Test Mode

For rapid POC testing, consider a `--test` flag on the orchestrator script that skips duplicate prevention and always shows the toast, regardless of whether it was shown before.

### 7. Validate Auto-Suppress Manually

Install the test software, then lock/unlock the PC. Confirm that the toast **does not** appear after installation. This is the key validation for the auto-suppress feature.

### 8. Keep the Description Field Clean

Place the human-readable description text above the `[TOAST-BEGIN]` block. End users in Software Center will see the description text; the toast block at the bottom is visually ignorable.

---

## Adopted Mitigations

The following mitigations address the downsides identified in the [Summary evaluation](SUMMARY-SoftwareCenter-ToastIntegration.md) and are incorporated into this concept design:

### 1. Clearly Delimited Block

**Addresses:** Description field pollution (end users seeing technical markup in Software Center).

The human-readable deployment description stays at the top of the field. A `[TOAST-BEGIN]`…`[TOAST-END]` block contains all toast configuration. End users who browse Software Center see the descriptive text first; the fenced block is visually distinct and can be ignored. Everything outside the markers is plain text and is never parsed.

### 2. Short-Form Tag Aliases

**Addresses:** Character length constraints in the SCCM description field.

Compact aliases are supported alongside full tag names: `h=` for `Headline`, `t=` for `Title`, `d=` for `Description`, `u=` for `Urgency`, etc. A mapping table in the client-side script converts short aliases to their full names internally before processing. This cuts tag overhead by 50–70%, leaving more room for the human-readable description and keeping the total within SCCM character limits. See the [Short-Form Alias Mapping Table](#short-form-alias-mapping-table) above for the complete list.

### 3. Lean on Defaults Aggressively

**Addresses:** Character length constraints and configuration complexity.

All parameters are unset by default except the two standard buttons ("Software Center öffnen" / "Schließen") and the Info-level images. Administrators are encouraged to specify **only the keys that differ** — in practice, most toasts need only `Title` and `Description`. Logo and Hero images are **pre-staged on the client** in 3 urgency-based sets, so there is no need to specify image URLs. This dramatically reduces the number of keys needed in the `[TOAST-BEGIN]` block.

### 4. Auto-Suppress on Successful Installation

**Addresses:** Toast lifecycle management and stale notifications.

The script checks the WMI `InstallState` before displaying a toast. Once the software is installed, the toast is automatically suppressed. This eliminates the need for manual `Deadline` management for most deployments and ensures users never see notifications for software they already have.

### 5. Log-Level Feedback with Fuzzy-Match Suggestions

**Addresses:** No authoring-time validation (typos in tag names silently fall back to defaults).

When the client-side script encounters an unrecognized key inside the `[TOAST-BEGIN]`…`[TOAST-END]` block, it logs a prominent warning with a fuzzy-match suggestion — for example: `WARNING: Unknown tag 'Headlne' — did you mean 'Headline'?`. The fuzzy-match compares against all known full tag names and short aliases. Administrators can:
- Review centralized logs to identify misconfigurations across the estate
- Run the script in **test mode** on a single machine to validate a new deployment's description before broad rollout

### 6. Structured Delimited Block with ConvertFrom-StringData

**Addresses:** Fragile regex-based parsing of free-text description fields.

Instead of regex-scanning the entire description, the toast config must live inside a clearly fenced block between `[TOAST-BEGIN]` and `[TOAST-END]` markers. Within this block, PowerShell's built-in `ConvertFrom-StringData` cmdlet parses simple `Key=Value` lines — no regex needed. This completely eliminates false matches from regular description text and handles escaping natively. The parser never touches text outside the fenced block.
