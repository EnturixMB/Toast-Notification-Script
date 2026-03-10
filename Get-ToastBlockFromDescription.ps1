# =============================================================================
# Function: Get-ToastBlockFromDescription
# Purpose:  Parses a Software Center deployment description for a
#           [TOAST-BEGIN]...[TOAST-END] fenced block, extracts Key=Value pairs
#           using ConvertFrom-StringData, and resolves short-form aliases to
#           their full tag names.
#
# Input:    [string] $Description – the full description text from an SCCM
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
        Write-Warning "Toast block is empty – no Key=Value pairs found"
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
            # Key is already a full tag name – keep as-is
            $ResolvedData[$TrimmedKey] = $ParsedData[$Key]
        }
    }

    return $ResolvedData
}
