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
│    This deployment installs 7-Zip 24.09 for all users.      │
│                                                             │
│    #toast                                                   │
│    [TOAST-BEGIN]                                             │
│    t=New Software Available                                 │
│    d=7-Zip 24.09 is now available. Please install it.       │
│    dl=2026-03-15                                            │
│    ab=Open Software Center                                  │
│    a=softwarecenter:Page=Applications                       │
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
│  │  Step 2: Two-pass parsing — Pass 1: Anchor detection   │  │
│  │  → Scan for #toast anchor (case-insensitive)           │  │
│  │  → If absent → skip deployment                         │  │
│  │  → Everything before #toast is ignored                 │  │
│  └────────────┬───────────────────────────────────────────┘  │
│               │                                              │
│               ▼                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Step 3: Two-pass parsing — Pass 2: Structured block   │  │
│  │  → Extract [TOAST-BEGIN]…[TOAST-END] block              │  │
│  │  → Parse Key=Value lines via ConvertFrom-StringData    │  │
│  │  → Resolve short-form aliases (h→Headline, t→Title…)   │  │
│  │  → Log warnings for unrecognized keys (fuzzy-match)    │  │
│  └────────────┬───────────────────────────────────────────┘  │
│               │                                              │
│               ▼                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Step 4: Generate in-memory XML configuration          │  │
│  │  → Build <Configuration> XML matching existing format  │  │
│  │  → Merge with base/default template                    │  │
│  │  → Images default to pre-staged local files            │  │
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

Toast configuration is embedded in the **Description** field of a Software Center deployment. The human-readable description stays at the top; the toast config lives below a clearly delimited block and can be visually ignored by end users even if they happen to scroll down.

### Delimited Block Convention

The toast configuration **must** be placed inside a fenced block marked by `[TOAST-BEGIN]` and `[TOAST-END]` markers at the bottom of the description field. Everything above `[TOAST-BEGIN]` is treated as regular description text and is never parsed. Within the block, each line is a simple `Key=Value` pair parsed with PowerShell's built-in `ConvertFrom-StringData` — no regex needed.

```
Human-readable description text here.
This part is shown to end users in Software Center.

[TOAST-BEGIN]
toast=true
Title=New Software Available
Description=Please install the latest update.
[TOAST-END]
```

> **Note:** The `#toast` anchor tag still serves as the primary trigger. The parser performs a **two-pass approach**: first, it scans for `#toast` anywhere in the description to decide whether to process the deployment at all. Only after finding `#toast` does it look for the `[TOAST-BEGIN]`…`[TOAST-END]` block and parse the structured `Key=Value` lines within it. Everything before `#toast` is plain text and is ignored entirely, dramatically reducing false-match surface area.

### Lean on Defaults

The base template already provides sensible defaults for all configuration values. Administrators should specify **only the tags that differ** from the template. In practice, most toasts need only `toast`, `Title`, and `Description` — well within any character limit.

**Logo and Hero images are pre-staged on the client** at deployment time (stored under `C:\ProgramData\ToastNotification\`). There is no need to specify `HeroImage` or `LogoImage` URLs unless a deployment-specific image is required. This eliminates external URL dependencies for the common case.

### Trigger Tag (Required)

| Tag | Short Alias | Purpose | Example |
|-----|-------------|---------|---------|
| `#toast` | — | **Activates** toast processing for this deployment. Without this tag, the deployment is ignored. Must appear somewhere in the description (can be above or inside the `[TOAST-BEGIN]` block). | `#toast` |

### Content Tags (Optional — override defaults)

| Tag | Short Alias | Maps to XML Field | Purpose | Example |
|-----|-------------|-------------------|---------|---------|
| `Headline=<text>` | `h=<text>` | `HeaderText` | The small header line at the top of the toast | `Headline=IT Department Notice` |
| `Title=<text>` | `t=<text>` | `TitleText` | The bold title text of the toast notification | `Title=New Software Available` |
| `Description=<text>` | `d=<text>` | `BodyText1` | The primary body text of the toast | `Description=7-Zip 24.09 is ready to install.` |
| `Body2=<text>` | `b2=<text>` | `BodyText2` | The secondary body text (additional detail) | `Body2=Please install at your earliest convenience.` |
| `Attribution=<text>` | `at=<text>` | `AttributionText` | Small text at the bottom of the toast | `Attribution=IT Helpdesk` |

### Scheduling Tags (Optional)

| Tag | Short Alias | Maps to XML Field | Purpose | Example |
|-----|-------------|-------------------|---------|---------|
| `Deadline=<date>` | `dl=<date>` | *(new concept)* | Show toast only until this date (ISO 8601). After the deadline passes, the toast is no longer displayed. | `Deadline=2026-03-15` |
| `StartDate=<date>` | `sd=<date>` | *(new concept)* | Show toast only from this date onward | `StartDate=2026-03-01` |

### Appearance Tags (Optional)

| Tag | Short Alias | Maps to XML Field | Purpose | Example |
|-----|-------------|-------------------|---------|---------|
| `HeroImage=<url>` | `hi=<url>` | `HeroImageName` | URL to the hero image shown at the top of the toast. **Not needed in most cases** — a default hero image is pre-staged on the client. | `HeroImage=https://corp.example.com/hero.png` |
| `LogoImage=<url>` | `li=<url>` | `LogoImageName` | URL to the logo/icon image. **Not needed in most cases** — a default logo is pre-staged on the client. | `LogoImage=https://corp.example.com/logo.png` |
| `Scenario=<type>` | `sc=<type>` | `Scenario` | Toast behavior: `reminder`, `short`, `long`, or `alarm` | `Scenario=reminder` |

### Action Tags (Optional)

| Tag | Short Alias | Maps to XML Field | Purpose | Example |
|-----|-------------|-------------------|---------|---------|
| `ActionButton=<text>` | `ab=<text>` | `ActionButton1` text | Label for the primary action button | `ActionButton=Install Now` |
| `Action=<protocol>` | `a=<protocol>` | `Action1` | Protocol/URL launched when the action button is clicked | `Action=softwarecenter:Page=Applications` |
| `ActionButton2=<text>` | `ab2=<text>` | `ActionButton2` text | Label for a secondary action button | `ActionButton2=Learn More` |
| `Action2=<url>` | `a2=<url>` | `Action2` | Protocol/URL for the second button | `Action2=https://wiki.corp.com/7zip` |
| `DismissButton=<text>` | `db=<text>` | `DismissButton` text | Label for the dismiss button | `DismissButton=Later` |

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
toast (trigger)          →   <Feature Name="Toast" Enabled="True" />
Headline (h)             →   <Text Name="HeaderText">value</Text>
Title (t)                →   <Text Name="TitleText">value</Text>
Description (d)          →   <Text Name="BodyText1">value</Text>
Body2 (b2)               →   <Text Name="BodyText2">value</Text>
Attribution (at)         →   <Text Name="AttributionText">value</Text>
Deadline (dl)            →   (New) Used for date-range filtering logic
StartDate (sd)           →   (New) Used for date-range filtering logic
HeroImage (hi)           →   <Option Name="HeroImageName" Value="value" />
LogoImage (li)           →   <Option Name="LogoImageName" Value="value" />
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

Any keys not specified in the delimited block fall back to values from a **base template** XML (a default config bundled with the script, pre-staged on the client). Logo and Hero images default to locally pre-staged files, so most deployments do not need to specify image URLs at all.

---

## Example: Software Center Description

### What the admin types in the SCCM Console (Deployment Description field):

```
This deployment installs 7-Zip 24.09 for all users.
Please install it from Software Center at your earliest convenience.

#toast
[TOAST-BEGIN]
Headline=IT Department
Title=New Software Available: 7-Zip 24.09
Description=A new version of 7-Zip has been published to Software Center. Please install it at your earliest convenience.
Body2=This update includes important security fixes.
Deadline=2026-03-15
ActionButton=Open Software Center
Action=softwarecenter:Page=Applications
DismissButton=Remind me later
Scenario=reminder
[TOAST-END]
```

> **Note:** The `#toast` anchor appears above the `[TOAST-BEGIN]` block. The parser first scans the entire description for `#toast` (pass 1). Only after finding it does it extract and parse the structured block between `[TOAST-BEGIN]` and `[TOAST-END]` using `ConvertFrom-StringData` (pass 2). The human-readable text at the top is never parsed.

### The same example using short-form aliases (saves ~50% characters):

```
This deployment installs 7-Zip 24.09 for all users.

#toast
[TOAST-BEGIN]
h=IT Department
t=New Software Available: 7-Zip 24.09
d=A new version of 7-Zip has been published to Software Center. Please install it at your earliest convenience.
b2=This update includes important security fixes.
dl=2026-03-15
ab=Open Software Center
a=softwarecenter:Page=Applications
db=Remind me later
sc=reminder
[TOAST-END]
```

### What the user sees:

A Windows toast notification with:
- **Header**: "IT Department"
- **Title**: "Good morning, John — New Software Available: 7-Zip 24.09"
- **Body**: "A new version of 7-Zip has been published to Software Center..."
- **Secondary text**: "This update includes important security fixes."
- **Buttons**: [Open Software Center] [Remind me later]
- **Hero image**: Pre-staged default corporate banner (from local client path)
- **Logo image**: Pre-staged default corporate logo (from local client path)

### The generated in-memory XML (produced by the script):

```xml
<?xml version="1.0" encoding="utf-8"?>
<Configuration>
    <Feature Name="Toast" Enabled="True" />
    <Feature Name="PendingRebootUptime" Enabled="False" />
    <Feature Name="WeeklyMessage" Enabled="False" />
    <Option Name="CustomNotificationApp" Enabled="True" Value="IT NOTIFICATIONS" />
    <Option Name="LogoImageName" Value="C:\ProgramData\ToastNotification\logo.png" />
    <Option Name="HeroImageName" Value="C:\ProgramData\ToastNotification\hero.png" />
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

> **Note:** `LogoImageName` and `HeroImageName` default to locally pre-staged images. They are only overridden if the admin explicitly provides a `LogoImage` or `HeroImage` key in the `[TOAST-BEGIN]` block.

---

## Minimal Example

The simplest possible description to trigger a toast with all defaults:

```
#toast
```

This triggers a toast on every logon using the base template defaults for all text and pre-staged images. No `[TOAST-BEGIN]` block is needed when all defaults are acceptable.

A slightly more useful minimal example:

```
Important security update available. Please install from Software Center.

#toast
[TOAST-BEGIN]
t=Please install the latest update
d=A critical security update is available in Software Center.
[TOAST-END]
```

> **Note:** Only two keys (`t` and `d`) are specified. Everything else — headline, images, buttons, scenario — comes from the base template defaults. This keeps the description field clean and well within character limits.

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
├── hero.png                             ← Pre-staged default hero image
├── logo.png                             ← Pre-staged default logo image
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

### Step 2 — Two-Pass Parsing: Filter for #toast Anchor (Pass 1)

The parser uses a **two-pass approach** to minimize false-match surface area:

**Pass 1 — Anchor Detection:**
1. Read the `Description` property of each deployment
2. Scan for the string `#toast` (case-insensitive) anywhere in the description
3. If `#toast` is **not** found → skip this deployment entirely
4. If `#toast` **is** found → proceed to Pass 2

Everything before `#toast` is treated as plain human-readable text and is **ignored entirely**. This scopes all further parsing to a small, predictable portion of the description rather than the full free-form text.

### Step 3 — Extract Configuration: Structured Delimited Block (Pass 2)

**Pass 2 — Structured Block Parsing:**

Instead of regex-scanning the entire description, the parser looks for a clearly fenced block between `[TOAST-BEGIN]` and `[TOAST-END]` markers:

1. Search for `[TOAST-BEGIN]` in the description text (after the `#toast` anchor)
2. If the markers are **not** found → use all base template defaults (the `#toast` anchor alone is enough to trigger a toast)
3. If the markers **are** found → extract the text between `[TOAST-BEGIN]` and `[TOAST-END]`
4. Parse the extracted block using PowerShell's built-in `ConvertFrom-StringData`, which handles simple `Key=Value` lines natively — **no regex needed**
5. Resolve short-form aliases (e.g., `h` → `Headline`, `t` → `Title`) using the alias mapping table
6. Map resolved keys to their corresponding XML fields (see Tag-to-XML Mapping)

This approach completely eliminates false matches from regular description text and handles special characters natively via `ConvertFrom-StringData`.

### Step 4 — Apply Date Filtering

If `Deadline` is present in the parsed keys:
- Parse the date value
- If today's date is **after** the deadline → skip this deployment (no toast)

If `StartDate` is present in the parsed keys:
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
- Log any unrecognized keys as warnings with fuzzy-match suggestions (see Error Handling)

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
| `#toast` found but no `[TOAST-BEGIN]` block | Log info, use all base template defaults |
| Invalid tag value (e.g., bad date) | Log warning, skip that tag, use default |
| Unrecognized key in `[TOAST-BEGIN]` block | Log warning with fuzzy-match suggestion (see below) |
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
| **Activation** | `#toast` anchor tag in description (two-pass parsing) |
| **Configuration** | Structured `Key=Value` lines inside `[TOAST-BEGIN]`…`[TOAST-END]` block; supports short-form aliases |
| **Parsing** | Pass 1: scan for `#toast` anchor. Pass 2: extract delimited block, parse with `ConvertFrom-StringData`, resolve aliases |
| **Toast Engine** | Existing `Remediate-ToastNotification.ps1` (no changes needed to core script) |
| **Config Format** | Keys are parsed, aliases resolved, and mapped to the existing XML `<Configuration>` format in-memory |
| **Defaults** | Base template provides all defaults; images pre-staged on client; admins specify only overrides |
| **Deployment** | One-time deployment of scheduled task + script files + pre-staged images to all clients |
| **Duplicate Prevention** | Hash-based tracking in `%APPDATA%` per user |
| **Multiple Toasts** | Each `#toast`-tagged deployment generates its own notification (max 3 per logon) |
| **Error Feedback** | Unrecognized keys logged as warnings with fuzzy-match suggestions |

---

## Adopted Mitigations

The following mitigations address the downsides identified in the [Summary evaluation](SUMMARY-SoftwareCenter-ToastIntegration.md) and are incorporated into this concept design:

### 1. Clearly Delimited Block at the Bottom

**Addresses:** Description field pollution (end users seeing technical markup in Software Center).

The human-readable deployment description stays at the top of the field. A `[TOAST-BEGIN]`…`[TOAST-END]` block at the bottom contains all toast configuration. End users who browse Software Center see the descriptive text first; the fenced block at the bottom is visually distinct and can be ignored. The `#toast` anchor tag acts as a separator convention — everything above it is plain text, everything below it (inside the markers) is configuration.

### 2. Short-Form Tag Aliases

**Addresses:** Character length constraints in the SCCM description field.

Compact aliases are supported alongside full tag names: `h=` for `Headline`, `t=` for `Title`, `d=` for `Description`, etc. A mapping table in the client-side script converts short aliases to their full names internally before processing. This cuts tag overhead by 50–70%, leaving more room for the human-readable description and keeping the total within SCCM character limits. See the [Short-Form Alias Mapping Table](#short-form-alias-mapping-table) above for the complete list.

### 3. Lean on Defaults Aggressively

**Addresses:** Character length constraints and configuration complexity.

The base template already provides sensible defaults for every configuration value. Administrators are encouraged to specify **only the keys that differ** from the template. In practice, most toasts need only `toast`, `Title`, and `Description` — well within any character limit. Logo and Hero images are **pre-staged on the client** at deployment time (stored under `C:\ProgramData\ToastNotification\`), so there is no need to specify image URLs in the description field unless a deployment-specific image is required. This dramatically reduces the number of keys needed in the `[TOAST-BEGIN]` block.

### 4. Log-Level Feedback with Fuzzy-Match Suggestions

**Addresses:** No authoring-time validation (typos in tag names silently fall back to defaults).

When the client-side script encounters an unrecognized key inside the `[TOAST-BEGIN]`…`[TOAST-END]` block, it logs a prominent warning with a fuzzy-match suggestion — for example: `WARNING: Unknown tag 'Headlne' — did you mean 'Headline'?`. The fuzzy-match compares against all known full tag names and short aliases. Administrators can:
- Review centralized logs to identify misconfigurations across the estate
- Run the script in **test mode** on a single machine to validate a new deployment's description before broad rollout

### 5. Structured Delimited Block with ConvertFrom-StringData

**Addresses:** Fragile regex-based parsing of free-text description fields.

Instead of regex-scanning the entire description, the toast config must live inside a clearly fenced block between `[TOAST-BEGIN]` and `[TOAST-END]` markers. Within this block, PowerShell's built-in `ConvertFrom-StringData` cmdlet parses simple `Key=Value` lines — no regex needed. This completely eliminates false matches from regular description text (e.g., `#` symbols in prose, special characters, multi-line values) and handles escaping natively. The parser never touches text outside the fenced block.

### 6. Two-Pass Parsing with Anchor Tag

**Addresses:** Fragile regex-based parsing; false-match surface area.

Parsing only begins after the `#toast` anchor is found (Pass 1). Everything before `#toast` is treated as plain text and ignored entirely. Only after confirming the anchor does the parser look for and extract the `[TOAST-BEGIN]`…`[TOAST-END]` block (Pass 2). This scopes all parsing to a small, predictable block of text rather than the full free-form description, dramatically reducing the risk of false matches or unintended tag extraction from regular prose.
