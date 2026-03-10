<#
.SYNOPSIS
    Orchestrator script for Software Center toast notifications.

.DESCRIPTION
    Entry point executed by the scheduled task. Queries Software Center for
    available deployments, parses [TOAST-BEGIN] blocks from descriptions,
    generates per-deployment XML configs, and invokes Remediate-ToastNotification.ps1
    to display toast notifications.

    All helper functions are defined inline (not dot-sourced) for simplicity.

.PARAMETER TestMode
    Skips duplicate prevention checks for rapid testing.

.NOTES
    Intended to run as a scheduled task on logon and workstation unlock.
    Maximum of 3 toasts per run to avoid notification fatigue.

.LINK
    https://github.com/imabdk/Toast-Notification-Script
#>

[CmdletBinding()]
param(
    [switch]$TestMode
)

# =============================================================================
# Configuration
# =============================================================================
$BasePath           = "C:\ProgramData\ToastNotification"
$BaseTemplatePath   = Join-Path $BasePath "config-toast-base-template.xml"
$RemediateScriptPath = Join-Path $BasePath "Remediate-ToastNotification.ps1"
$LogPath            = Join-Path $BasePath "Logs\SoftwareCenterToast.log"
$MaxToastsPerRun    = 3

# =============================================================================
# Function: Write-ToastLog
# Purpose:  Appends a timestamped message to the log file and writes to console.
# =============================================================================
function Write-ToastLog {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry  = "[$timestamp] $Message"

    # Ensure the Logs directory exists
    $logDir = Split-Path -Path $LogPath -Parent
    if (-not (Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # Append to log file
    Add-Content -Path $LogPath -Value $logEntry -Encoding UTF8

    # Also write to console
    Write-Output $logEntry
}

# =============================================================================
# Function: Get-ToastBlockFromDescription
# Purpose:  Parses a Software Center deployment description for a
#           [TOAST-BEGIN]...[TOAST-END] fenced block, extracts Key=Value pairs
#           using ConvertFrom-StringData, and resolves short-form aliases to
#           their full tag names.
#
# Input:    [string] $Description - the full description text from an SCCM
#           deployment (e.g. retrieved via Get-CimInstance).
#
# Output:   [hashtable] of resolved toast parameters, or $null when no
#           [TOAST-BEGIN] marker is found.
#
# Alias mapping (short -> full):
#   h=Headline  t=Title  d=Description  b2=Body2  at=Attribution
#   dl=Deadline  sd=StartDate  hi=HeroImage  li=LogoImage  u=Urgency
#   sc=Scenario  ab=ActionButton  a=Action  ab2=ActionButton2
#   a2=Action2  db=DismissButton
# =============================================================================
function Get-ToastBlockFromDescription {
    param(
        [string]$Description
    )

    # Short-form alias to full tag-name mapping
    $AliasMap = @{
        'h'   = 'Headline'
        't'   = 'Title'
        'd'   = 'Description'
        'b2'  = 'Body2'
        'at'  = 'Attribution'
        'dl'  = 'Deadline'
        'sd'  = 'StartDate'
        'hi'  = 'HeroImage'
        'li'  = 'LogoImage'
        'u'   = 'Urgency'
        'sc'  = 'Scenario'
        'ab'  = 'ActionButton'
        'a'   = 'Action'
        'ab2' = 'ActionButton2'
        'a2'  = 'Action2'
        'db'  = 'DismissButton'
    }

    # Case-insensitive search for the [TOAST-BEGIN] marker
    $BeginPattern = '\[TOAST-BEGIN\]'
    $EndPattern   = '\[TOAST-END\]'

    if ($Description -notmatch $BeginPattern) {
        return $null
    }

    # Extract everything between [TOAST-BEGIN] and [TOAST-END]
    if ($Description -match '(?si)\[TOAST-BEGIN\]\s*(.*?)\s*\[TOAST-END\]') {
        $RawBlock = $Matches[1]
    }
    else {
        Write-Warning "Found [TOAST-BEGIN] but no matching [TOAST-END] marker"
        return $null
    }

    # Filter out empty and whitespace-only lines before parsing
    $CleanedLines = ($RawBlock -split '\r?\n') |
        Where-Object { $_.Trim() -ne '' }

    if ($CleanedLines.Count -eq 0) {
        Write-Warning "Toast block is empty - no Key=Value pairs found"
        return $null
    }

    $CleanedBlock = $CleanedLines -join "`n"

    # Parse Key=Value pairs using ConvertFrom-StringData
    try {
        $ParsedData = ConvertFrom-StringData -StringData $CleanedBlock
    }
    catch {
        Write-Warning "Failed to parse toast block with ConvertFrom-StringData: $_"
        return $null
    }

    # Resolve short-form aliases to full tag names
    $ResolvedData = @{}
    foreach ($Key in $ParsedData.Keys) {
        $TrimmedKey = $Key.Trim()
        if ($AliasMap.ContainsKey($TrimmedKey)) {
            $ResolvedData[$AliasMap[$TrimmedKey]] = $ParsedData[$Key]
        }
        else {
            # Key is already a full tag name - keep as-is
            $ResolvedData[$TrimmedKey] = $ParsedData[$Key]
        }
    }

    return $ResolvedData
}

# =============================================================================
# Function: New-ToastXmlFromTags
# Purpose:  Takes a hashtable of parsed tags and the base template XML path,
#           overlays tag values onto the XML, and returns the modified [xml].
#
# Input:    [hashtable] $Tags          - parsed tag key-value pairs
#           [string]    $BaseTemplatePath - path to config-toast-base-template.xml
#
# Output:   [xml] object ready for Remediate-ToastNotification.ps1
# =============================================================================
function New-ToastXmlFromTags {
    param(
        [hashtable]$Tags,
        [string]$BaseTemplatePath
    )

    # Load the base template XML
    [xml]$xml = Get-Content -Path $BaseTemplatePath -Encoding UTF8

    # The language node is en-US (German text is used in this block because
    # MultiLanguageSupport=False causes Remediate-ToastNotification.ps1 to
    # always read from en-US)
    $langNode = $xml.Configuration.'en-US'
    $ImageBasePath = "C:\ProgramData\ToastNotification\Images"

    # ---- Handle Urgency tag (sets default images based on level) ----
    if ($Tags.ContainsKey('Urgency')) {
        $urgency = $Tags['Urgency'].ToLower()
        switch ($urgency) {
            'info'     { $heroFile = 'hero-info.png';     $logoFile = 'logo-info.png'     }
            'warnung'  { $heroFile = 'hero-warnung.png';  $logoFile = 'logo-warnung.png'  }
            'kritisch' { $heroFile = 'hero-kritisch.png'; $logoFile = 'logo-kritisch.png' }
            default {
                Write-Warning "Unknown Urgency value '$urgency' - falling back to 'info'."
                $heroFile = 'hero-info.png'
                $logoFile = 'logo-info.png'
            }
        }
        $heroPath = Join-Path $ImageBasePath $heroFile
        $logoPath = Join-Path $ImageBasePath $logoFile

        # Set HeroImageName and LogoImageName Option values using SetAttribute to avoid
        # conflicts with the read-only XmlNode.Value .NET property when using the
        # PowerShell XML type adapter.
        $heroNode = $xml.Configuration.Option | Where-Object { $_.Name -eq 'HeroImageName' }
        if ($null -ne $heroNode) { $heroNode.SetAttribute('Value', $heroPath) }
        $logoNode = $xml.Configuration.Option | Where-Object { $_.Name -eq 'LogoImageName' }
        if ($null -ne $logoNode) { $logoNode.SetAttribute('Value', $logoPath) }
    }

    # ---- Tag-to-XML mapping for text nodes in en-US ----
    $textMapping = @{
        'Headline'      = 'HeaderText'
        'Title'         = 'TitleText'
        'Description'   = 'BodyText1'
        'Body2'         = 'BodyText2'
        'Attribution'   = 'AttributionText'
        'ActionButton'  = 'ActionButton1'
        'ActionButton2' = 'ActionButton2'
        'DismissButton' = 'DismissButton'
    }

    foreach ($tagName in $textMapping.Keys) {
        if ($Tags.ContainsKey($tagName)) {
            $xmlTextName = $textMapping[$tagName]
            $textNode = $langNode.Text | Where-Object { $_.Name -eq $xmlTextName }
            if ($null -ne $textNode) {
                $textNode.InnerText = $Tags[$tagName]
            }
        }
    }

    # ---- Enable ActionButton1 if ActionButton tag is provided ----
    if ($Tags.ContainsKey('ActionButton')) {
        $optNode = $xml.Configuration.Option | Where-Object { $_.Name -eq 'ActionButton1' }
        if ($null -ne $optNode) { $optNode.Enabled = 'True' }
    }

    # ---- Enable ActionButton2 if ActionButton2 tag is provided ----
    if ($Tags.ContainsKey('ActionButton2')) {
        $optNode = $xml.Configuration.Option | Where-Object { $_.Name -eq 'ActionButton2' }
        if ($null -ne $optNode) { $optNode.Enabled = 'True' }
    }

    # HeroImage (explicit override takes precedence over Urgency)
    if ($Tags.ContainsKey('HeroImage')) {
        $heroNode = $xml.Configuration.Option | Where-Object { $_.Name -eq 'HeroImageName' }
        if ($null -ne $heroNode) { $heroNode.SetAttribute('Value', $Tags['HeroImage']) }
    }

    # LogoImage (explicit override takes precedence over Urgency)
    if ($Tags.ContainsKey('LogoImage')) {
        $logoNode = $xml.Configuration.Option | Where-Object { $_.Name -eq 'LogoImageName' }
        if ($null -ne $logoNode) { $logoNode.SetAttribute('Value', $Tags['LogoImage']) }
    }

    # Scenario
    if ($Tags.ContainsKey('Scenario')) {
        ($xml.Configuration.Option | Where-Object { $_.Name -eq 'Scenario' }).Type = $Tags['Scenario']
    }

    # Action (Action1)
    if ($Tags.ContainsKey('Action')) {
        $actionNode = $xml.Configuration.Option | Where-Object { $_.Name -eq 'Action1' }
        if ($null -ne $actionNode) { $actionNode.SetAttribute('Value', $Tags['Action']) }
    }

    # Action2
    if ($Tags.ContainsKey('Action2')) {
        $action2Node = $xml.Configuration.Option | Where-Object { $_.Name -eq 'Action2' }
        if ($null -ne $action2Node) { $action2Node.SetAttribute('Value', $Tags['Action2']) }
    }

    return $xml
}

# =============================================================================
# Function: Get-SoftwareCenterDeployments
# Purpose:  Queries SCCM/MECM client for available Software Center deployments.
#           Returns a list of uninstalled deployments with Name, Description,
#           IsInstalled, and Type properties.
# =============================================================================
function Get-SoftwareCenterDeployments {
    [CmdletBinding()]
    param()

    $Namespace = 'root\ccm\ClientSDK'

    # ------------------------------------------------------------------
    # 1. Verify that the SCCM client WMI namespace is reachable
    # ------------------------------------------------------------------
    try {
        $null = Get-CimInstance -Namespace $Namespace -ClassName 'CCM_Application' -ErrorAction Stop
    }
    catch {
        Write-Warning "SCCM client WMI namespace '$Namespace' is not available. Error: $($_.Exception.Message)"
        return $null
    }

    # ------------------------------------------------------------------
    # 2. Query CCM_Application (Applications)
    # ------------------------------------------------------------------
    $applications = [System.Collections.Generic.List[PSCustomObject]]::new()
    try {
        $appResults = Get-CimInstance -Namespace $Namespace -ClassName 'CCM_Application' -ErrorAction Stop |
            Select-Object Name, Description, InstallState

        if ($appResults) {
            foreach ($app in @($appResults)) {
                $applications.Add([PSCustomObject]@{
                    Name        = $app.Name
                    Description = $app.Description
                    IsInstalled = ($app.InstallState -eq 'Installed')
                    Type        = 'Application'
                })
            }
        }
    }
    catch {
        Write-Warning "Failed to query CCM_Application: $($_.Exception.Message)"
    }

    # ------------------------------------------------------------------
    # 3. Query CCM_Program (Packages / Programs)
    # ------------------------------------------------------------------
    $programs = [System.Collections.Generic.List[PSCustomObject]]::new()
    try {
        $pgmResults = Get-CimInstance -Namespace $Namespace -ClassName 'CCM_Program' -ErrorAction Stop |
            Select-Object Name, Description, ResolvedState

        if ($pgmResults) {
            foreach ($pgm in @($pgmResults)) {
                $programs.Add([PSCustomObject]@{
                    Name        = $pgm.Name
                    Description = $pgm.Description
                    IsInstalled = ($pgm.ResolvedState -eq 'Installed')
                    Type        = 'Program'
                })
            }
        }
    }
    catch {
        Write-Warning "Failed to query CCM_Program: $($_.Exception.Message)"
    }

    # ------------------------------------------------------------------
    # 4. Combine and filter out already-installed deployments
    # ------------------------------------------------------------------
    $allDeployments = @($applications) + @($programs)

    $available = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($dep in $allDeployments) {
        if ($dep.IsInstalled) {
            Write-Verbose "Deployment '$($dep.Name)' already installed - toast suppressed."
        }
        else {
            $available.Add($dep)
        }
    }

    return $available
}

# =============================================================================
# Function: Test-ToastAlreadyShown
# Purpose:  Checks if a toast for a given deployment has already been shown
#           by looking up a SHA256 hash in a JSON tracking file.
# =============================================================================
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

# =============================================================================
# Function: Set-ToastShown
# Purpose:  Records a toast as shown by adding a SHA256 hash entry to a JSON
#           tracking file.
# =============================================================================
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

# =============================================================================
# Main Execution Flow
# =============================================================================
Write-ToastLog -Message "Starting Software Center toast notification check..."

# Step 1: Query Software Center deployments
$deployments = Get-SoftwareCenterDeployments

if ($null -eq $deployments -or $deployments.Count -eq 0) {
    Write-ToastLog -Message "No uninstalled deployments found."
    exit 0
}

Write-ToastLog -Message "Found $($deployments.Count) uninstalled deployment(s)."

# Step 2: Process each deployment
$toastCount = 0

foreach ($deployment in $deployments) {
    # Check max toasts per run
    if ($toastCount -ge $MaxToastsPerRun) {
        Write-ToastLog -Message "Max toasts reached ($MaxToastsPerRun). Stopping."
        break
    }

    # Parse the description for a [TOAST-BEGIN] block
    $tags = Get-ToastBlockFromDescription -Description $deployment.Description
    if ($null -eq $tags) {
        Write-ToastLog -Message "No [TOAST-BEGIN] block in '$($deployment.Name)'."
        continue
    }

    # Check duplicate prevention (skip in TestMode)
    if (-not $TestMode) {
        $alreadyShown = Test-ToastAlreadyShown -DeploymentName $deployment.Name -Description $deployment.Description
        if ($alreadyShown) {
            Write-ToastLog -Message "Toast already shown for '$($deployment.Name)'."
            continue
        }
    }

    # Generate the in-memory XML configuration
    $xml = New-ToastXmlFromTags -Tags $tags -BaseTemplatePath $BaseTemplatePath

    # Save XML to a temp file using GetTempPath() (long path) to avoid 8.3 short-name
    # issues (e.g. AFDE3~1.MAB) that cause Remove-Item to fail on some systems.
    $tempConfig = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "toast-config-$(Get-Random).xml")
    $xml.Save($tempConfig)

    # Invoke the toast engine
    $toastSuccess = $false
    try {
        Write-ToastLog -Message "Invoking toast for '$($deployment.Name)'..."
        powershell.exe -ExecutionPolicy Bypass -Command "& '$RemediateScriptPath' -Config '$tempConfig'"
        $toastSuccess = ($LASTEXITCODE -eq 0)
        if (-not $toastSuccess) {
            Write-ToastLog -Message "Toast engine exited with code $LASTEXITCODE for '$($deployment.Name)'."
        }
    }
    catch {
        Write-ToastLog -Message "Failed to invoke toast for '$($deployment.Name)': $_"
    }

    # Clean up temp config file
    try {
        if (Test-Path -Path $tempConfig) {
            Remove-Item -Path $tempConfig -Force -ErrorAction Stop
        }
    }
    catch {
        # Ignore cleanup failures - temp file will be cleaned up by the OS eventually
    }

    # Record toast as shown and update count only when the toast was actually displayed
    if ($toastSuccess) {
        Set-ToastShown -DeploymentName $deployment.Name -Description $deployment.Description
        $toastCount++
        Write-ToastLog -Message "Toast displayed for '$($deployment.Name)'."
    }
}

Write-ToastLog -Message "Completed. $toastCount toast(s) displayed."
exit 0
