# =============================================================================
# Function: New-ToastXmlFromTags
# Purpose:  Takes a parsed tag hashtable (from Get-ToastBlockFromDescription)
#           and a base XML template path, overlays the tag values onto the
#           XML, and returns the modified [xml] object compatible with
#           Remediate-ToastNotification.ps1.
#
# Input:    [hashtable] $Tags           - resolved toast parameters
#           [string]    $BaseTemplatePath - path to config-toast-base-template.xml
#
# Output:   [xml] object with tag values applied
#
# Tag-to-XML mapping:
#   Headline      -> <Text Name="HeaderText">
#   Title         -> <Text Name="TitleText">
#   Description   -> <Text Name="BodyText1">
#   Body2         -> <Text Name="BodyText2">
#   Attribution   -> <Text Name="AttributionText">
#   HeroImage     -> <Option Name="HeroImageName" Value="...">
#   LogoImage     -> <Option Name="LogoImageName" Value="...">
#   Scenario      -> <Option Name="Scenario" Type="...">
#   ActionButton  -> <Text Name="ActionButton1"> + Enabled="True"
#   Action        -> <Option Name="Action1" Value="...">
#   ActionButton2 -> <Text Name="ActionButton2"> + Enabled="True"
#   Action2       -> <Option Name="Action2" Value="...">
#   DismissButton -> <Text Name="DismissButton">
#   Urgency       -> sets HeroImageName + LogoImageName from image set
# =============================================================================
function New-ToastXmlFromTags {
    param(
        [hashtable]$Tags,
        [string]$BaseTemplatePath
    )

    # Validate the base template file exists
    if (-NOT (Test-Path -Path $BaseTemplatePath)) {
        throw "Base template not found: $BaseTemplatePath"
    }

    # Load the base template XML
    [xml]$xml = Get-Content -Path $BaseTemplatePath -Encoding UTF8

    # The template uses en-US as the language node (with German text)
    # because MultiLanguageSupport is set to False
    $langNode = $xml.Configuration.'en-US'

    # Image base path for urgency-based default images
    $ImageBasePath = 'C:\ProgramData\ToastNotification\Images'

    # Urgency-to-image mapping
    $UrgencyMap = @{
        'info'     = @{ Hero = 'hero-info.png';     Logo = 'logo-info.png' }
        'warnung'  = @{ Hero = 'hero-warnung.png';   Logo = 'logo-warnung.png' }
        'kritisch' = @{ Hero = 'hero-kritisch.png';  Logo = 'logo-kritisch.png' }
    }

    # Tag name to XML Text element name mapping
    $TextTagMap = @{
        'Headline'      = 'HeaderText'
        'Title'         = 'TitleText'
        'Description'   = 'BodyText1'
        'Body2'         = 'BodyText2'
        'Attribution'   = 'AttributionText'
        'DismissButton' = 'DismissButton'
    }

    # --- Apply Urgency first (so explicit HeroImage/LogoImage can override) ---
    if ($Tags.ContainsKey('Urgency')) {
        $urgencyValue = $Tags['Urgency'].ToLower()
        if ($UrgencyMap.ContainsKey($urgencyValue)) {
            $heroFile = $UrgencyMap[$urgencyValue].Hero
            $logoFile = $UrgencyMap[$urgencyValue].Logo
        }
        else {
            Write-Warning "Unknown Urgency value '$($Tags['Urgency'])' - falling back to 'info'"
            $heroFile = $UrgencyMap['info'].Hero
            $logoFile = $UrgencyMap['info'].Logo
        }

        $heroOption = $xml.Configuration.Option | Where-Object { $_.Name -eq 'HeroImageName' }
        if ($null -ne $heroOption) {
            $heroOption.Value = "$ImageBasePath\$heroFile"
        }

        $logoOption = $xml.Configuration.Option | Where-Object { $_.Name -eq 'LogoImageName' }
        if ($null -ne $logoOption) {
            $logoOption.Value = "$ImageBasePath\$logoFile"
        }
    }

    # --- Apply text tags ---
    foreach ($tagName in $TextTagMap.Keys) {
        if ($Tags.ContainsKey($tagName)) {
            $xmlElementName = $TextTagMap[$tagName]
            $textElement = $langNode.Text | Where-Object { $_.Name -eq $xmlElementName }
            if ($null -ne $textElement) {
                $textElement.InnerText = $Tags[$tagName]
            }
        }
    }

    # --- Apply ActionButton (Text + Option Enabled) ---
    if ($Tags.ContainsKey('ActionButton')) {
        $ab1Text = $langNode.Text | Where-Object { $_.Name -eq 'ActionButton1' }
        if ($null -ne $ab1Text) {
            $ab1Text.InnerText = $Tags['ActionButton']
        }
        $ab1Option = $xml.Configuration.Option | Where-Object { $_.Name -eq 'ActionButton1' }
        if ($null -ne $ab1Option) {
            $ab1Option.Enabled = 'True'
        }
    }

    # --- Apply Action (Option Value) ---
    if ($Tags.ContainsKey('Action')) {
        $action1Option = $xml.Configuration.Option | Where-Object { $_.Name -eq 'Action1' }
        if ($null -ne $action1Option) {
            $action1Option.Value = $Tags['Action']
        }
    }

    # --- Apply ActionButton2 (Text + Option Enabled) ---
    if ($Tags.ContainsKey('ActionButton2')) {
        $ab2Text = $langNode.Text | Where-Object { $_.Name -eq 'ActionButton2' }
        if ($null -ne $ab2Text) {
            $ab2Text.InnerText = $Tags['ActionButton2']
        }
        $ab2Option = $xml.Configuration.Option | Where-Object { $_.Name -eq 'ActionButton2' }
        if ($null -ne $ab2Option) {
            $ab2Option.Enabled = 'True'
        }
    }

    # --- Apply Action2 (Option Value) ---
    if ($Tags.ContainsKey('Action2')) {
        $action2Option = $xml.Configuration.Option | Where-Object { $_.Name -eq 'Action2' }
        if ($null -ne $action2Option) {
            $action2Option.Value = $Tags['Action2']
        }
    }

    # --- Apply HeroImage (overrides Urgency if both specified) ---
    if ($Tags.ContainsKey('HeroImage')) {
        $heroOption = $xml.Configuration.Option | Where-Object { $_.Name -eq 'HeroImageName' }
        if ($null -ne $heroOption) {
            $heroOption.Value = $Tags['HeroImage']
        }
    }

    # --- Apply LogoImage (overrides Urgency if both specified) ---
    if ($Tags.ContainsKey('LogoImage')) {
        $logoOption = $xml.Configuration.Option | Where-Object { $_.Name -eq 'LogoImageName' }
        if ($null -ne $logoOption) {
            $logoOption.Value = $Tags['LogoImage']
        }
    }

    # --- Apply Scenario (Option Type attribute) ---
    if ($Tags.ContainsKey('Scenario')) {
        $scenarioOption = $xml.Configuration.Option | Where-Object { $_.Name -eq 'Scenario' }
        if ($null -ne $scenarioOption) {
            $scenarioOption.Type = $Tags['Scenario']
        }
    }

    return $xml
}
