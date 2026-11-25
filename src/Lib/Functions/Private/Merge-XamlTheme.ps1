function Merge-XamlTheme {
    <#
    .SYNOPSIS
        Puts the shared theme's resources (ui\Theme.xaml) into a window's XAML, before it is loaded.

    .DESCRIPTION
        The windows are loaded from XAML text through an XmlNodeReader, which has no base address,
        so a <ResourceDictionary Source="Theme.xaml"/> in a window could not be resolved. Merging at
        the XML level instead has two more advantages: StaticResource references to theme keys work
        as if the window had declared them, and this is plain XML work that is tested without WPF.

        Every element of the theme dictionary is copied to the start of the root element's resources
        (Window.Resources, UserControl.Resources), so the window's own resources can build on them
        (BasedOn="{StaticResource Theme...}"). When the resources hold a single ResourceDictionary,
        that dictionary is used. Resources that are missing are created as the root's first child,
        ahead of any content that could reference them.

        A theme resource is left out when the window already has one with the same key: the same
        x:Key, or an implicit style (or template) for the same type. The window's own always wins.

        The XAML is changed in place.

    .PARAMETER Xaml
        The window's XAML.

    .PARAMETER Theme
        The theme dictionary's XAML.

    .OUTPUTS
        [int] How many theme resources were added.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlDocument]$Xaml,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [System.Xml.XmlDocument]$Theme
    )

    if ($null -eq $Theme -or $null -eq $Theme.DocumentElement -or $null -eq $Xaml.DocumentElement) {
        return 0
    }

    $Private:Target = Get-XamlResourceContainer -Xaml $Xaml
    $Private:Existing = @(Get-XamlResourceElement -Container $Private:Target | ForEach-Object { Get-XamlResourceKey -Element $_ })

    $Private:Anchor = @(Get-XamlResourceElement -Container $Private:Target | Select-Object -First 1)[0]
    $Private:Added = 0
    foreach ($Private:Resource in @(Get-XamlResourceElement -Container $Theme.DocumentElement)) {
        if ((Get-XamlResourceKey -Element $Private:Resource) -in $Private:Existing) {
            continue
        }

        $Private:Copy = $Xaml.ImportNode($Private:Resource, $true)
        if ($null -eq $Private:Anchor) {
            $null = $Private:Target.AppendChild($Private:Copy)
        }
        else {
            $null = $Private:Target.InsertBefore($Private:Copy, $Private:Anchor)
        }
        $Private:Added++
    }

    return $Private:Added
}

function Get-XamlResourceContainer {
    <#
    .SYNOPSIS
        The element a window's resources go in: its <Root.Resources>, or the single
        ResourceDictionary in it. Created as the root's first child when the window has none.

    .OUTPUTS
        [System.Xml.XmlElement]
    #>
    [CmdletBinding()]
    [OutputType([System.Xml.XmlElement])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlDocument]$Xaml
    )

    $Private:Root = $Xaml.DocumentElement
    $Private:Name = "{0}.Resources" -f $Private:Root.LocalName
    $Private:Resources = @($Private:Root.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] -and $_.LocalName -eq $Private:Name -and $_.NamespaceURI -eq $Private:Root.NamespaceURI })[0]

    if ($null -eq $Private:Resources) {
        $Private:Resources = $Xaml.CreateElement($Private:Name, $Private:Root.NamespaceURI)
        $null = $Private:Root.PrependChild($Private:Resources)
        return $Private:Resources
    }

    $Private:Children = @(Get-XamlResourceElement -Container $Private:Resources)
    if ($Private:Children.Count -eq 1 -and $Private:Children[0].LocalName -eq "ResourceDictionary") {
        return $Private:Children[0]
    }
    return $Private:Resources
}

function Get-XamlResourceElement {
    <#
    .SYNOPSIS
        The resources in a resources element: its child elements, without comments and without the
        dictionary's own property elements (ResourceDictionary.MergedDictionaries).

    .OUTPUTS
        [System.Xml.XmlElement[]]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlElement]$Container
    )

    @($Container.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] -and $_.LocalName -notlike "*.*" })
}

function Get-XamlResourceKey {
    <#
    .SYNOPSIS
        What identifies a resource in a dictionary: its x:Key, or for an implicit style or template
        the type it applies to.

    .DESCRIPTION
        "{x:Type Button}" and "Button" are the same type, so the markup extension is unwrapped. An
        element with neither (which a dictionary would reject anyway) gets a key of its own, so it is
        never mistaken for another.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlElement]$Element
    )

    $Private:Key = $Element.GetAttribute("Key", "http://schemas.microsoft.com/winfx/2006/xaml")
    if (-not [string]::IsNullOrEmpty($Private:Key)) {
        return "key:{0}" -f $Private:Key
    }

    foreach ($Private:Attribute in @("TargetType", "DataType")) {
        $Private:Type = $Element.GetAttribute($Private:Attribute)
        if (-not [string]::IsNullOrEmpty($Private:Type)) {
            return "type:{0}" -f ($Private:Type -replace '^\{x:Type\s+(.+?)\s*\}$', '$1')
        }
    }

    return "element:{0}" -f [guid]::NewGuid()
}

function Get-XamlTheme {
    <#
    .SYNOPSIS
        The shared theme dictionary (lib\ui\Theme.xaml), read once per session.

    .DESCRIPTION
        $null, logged, when it cannot be read: a window then loads without the
        theme - and fails on its first theme key, which names the problem - rather than this
        swallowing it.

    .OUTPUTS
        [System.Xml.XmlDocument] or $null.
    #>
    [CmdletBinding()]
    [OutputType([System.Xml.XmlDocument])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\Theme.xaml")
    )

    if ($null -ne $Script:XamlThemeCache -and $Script:XamlThemeCache.Path -eq $Path) {
        return $Script:XamlThemeCache.Theme
    }

    try {
        [xml]$Private:Theme = Get-Content -Path $Path -Raw -ErrorAction Stop
        $Script:XamlThemeCache = [PSCustomObject]@{ Path = $Path; Theme = $Private:Theme }
        return $Private:Theme
    }
    catch {
        "The theme '{0}' could not be read: {1}" -f $Path, $_.Exception.Message | Write-LogOutput -LogType DEBUG
        return $null
    }
}
