#Requires -Version 7.0
# The shared look (src/Lib/ui/Theme.xaml) and how it reaches every window. Parsed as XML, not loaded
# into WPF, so this runs in the headless lane; what it guards is what would otherwise only fail when a
# window opens: a StaticResource key that no longer resolves.

BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $Script:UiPath = [System.IO.Path]::Combine($Script:RepositoryRoot, "src", "Lib", "ui")
    . ([System.IO.Path]::Combine($Script:RepositoryRoot, "src", "Lib", "Functions", "Private", "Merge-XamlTheme.ps1"))
    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)]$Message, $LogType) process { $script:Log += , [PSCustomObject]@{ Message = $Message; LogType = $LogType } } }

    $Script:XNs = "http://schemas.microsoft.com/winfx/2006/xaml"
    $Script:ThemePath = Join-Path $Script:UiPath "Theme.xaml"

    function script:New-TestXaml {
        param([string]$Body)
        [xml]('<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">{0}</Window>' -f $Body)
    }
    function script:New-TestTheme {
        [xml]@'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <!-- a comment is not a resource -->
    <SolidColorBrush x:Key="Theme.A" Color="Red" />
    <Style TargetType="TabItem"><Setter Property="Foreground" Value="Red" /></Style>
    <Style x:Key="Theme.B" TargetType="Button" />
</ResourceDictionary>
'@
    }
    function script:Get-ResourceSummary {
        param([xml]$Xaml)
        @(Get-XamlResourceElement -Container (Get-XamlResourceContainer -Xaml $Xaml) | ForEach-Object { Get-XamlResourceKey -Element $_ })
    }
}

Describe 'Merge-XamlTheme' -Tag 'Unit' {
    It 'Should put the theme''s resources ahead of the window''s own, so the window can build on them' {
        $Xaml = New-TestXaml -Body '<Window.Resources><Style x:Key="Own" BasedOn="{StaticResource Theme.B}" TargetType="Button" /></Window.Resources><Grid />'

        Merge-XamlTheme -Xaml $Xaml -Theme (New-TestTheme) | Should -Be 3

        Get-ResourceSummary -Xaml $Xaml | Should -Be @("key:Theme.A", "type:TabItem", "key:Theme.B", "key:Own")
    }

    It 'Should keep the window''s own resource for a key or a type it already has' {
        $Xaml = New-TestXaml -Body '<Window.Resources><SolidColorBrush x:Key="Theme.A" Color="Blue" /><Style TargetType="{x:Type TabItem}" /></Window.Resources>'

        Merge-XamlTheme -Xaml $Xaml -Theme (New-TestTheme) | Should -Be 1

        Get-ResourceSummary -Xaml $Xaml | Should -Be @("key:Theme.B", "key:Theme.A", "type:TabItem")
        $Xaml.DocumentElement.FirstChild.ChildNodes[1].GetAttribute("Color") | Should -Be "Blue"
    }

    It 'Should create the resources as the first child when the window has none' {
        $Xaml = New-TestXaml -Body '<Grid />'

        Merge-XamlTheme -Xaml $Xaml -Theme (New-TestTheme) | Should -Be 3

        $Xaml.DocumentElement.FirstChild.LocalName | Should -Be "Window.Resources"
        $Xaml.DocumentElement.ChildNodes[1].LocalName | Should -Be "Grid"
    }

    It 'Should merge into the single ResourceDictionary the resources hold' {
        $Xaml = New-TestXaml -Body '<Window.Resources><ResourceDictionary><ResourceDictionary.MergedDictionaries /><Style x:Key="Own" TargetType="Button" /></ResourceDictionary></Window.Resources>'

        $null = Merge-XamlTheme -Xaml $Xaml -Theme (New-TestTheme)

        $Dictionary = $Xaml.DocumentElement.FirstChild.FirstChild
        @($Dictionary.ChildNodes | ForEach-Object LocalName) | Should -Be @("ResourceDictionary.MergedDictionaries", "SolidColorBrush", "Style", "Style", "Style")
    }

    It 'Should add nothing a second time' {
        $Xaml = New-TestXaml -Body '<Grid />'
        $null = Merge-XamlTheme -Xaml $Xaml -Theme (New-TestTheme)

        Merge-XamlTheme -Xaml $Xaml -Theme (New-TestTheme) | Should -Be 0
    }

    It 'Should leave the window alone without a theme (<Case>)' -ForEach @(
        @{ Case = 'none'; Empty = $false }
        @{ Case = 'an empty document'; Empty = $true }
    ) {
        $Xaml = New-TestXaml -Body '<Grid />'
        $Theme = if ($Empty) { [System.Xml.XmlDocument]::new() } else { $null }

        Merge-XamlTheme -Xaml $Xaml -Theme $Theme | Should -Be 0
        $Xaml.DocumentElement.FirstChild.LocalName | Should -Be "Grid"
    }

    It 'Should copy a resource whole, with what is inside it' {
        $Xaml = New-TestXaml -Body '<Grid />'
        $null = Merge-XamlTheme -Xaml $Xaml -Theme (New-TestTheme)

        $Style = @($Xaml.DocumentElement.FirstChild.ChildNodes | Where-Object { $_.GetAttribute("TargetType") -eq "TabItem" })[0]
        $Style.FirstChild.GetAttribute("Value") | Should -Be "Red"
    }

    It 'Should give an element without a key or a type a key of its own' {
        $Doc = [xml]'<a xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"><b /><b /></a>'
        (Get-XamlResourceKey -Element $Doc.DocumentElement.ChildNodes[0]) | Should -Not -Be (Get-XamlResourceKey -Element $Doc.DocumentElement.ChildNodes[1])
    }
}

Describe 'Get-XamlTheme' -Tag 'Unit' {
    BeforeEach {
        $script:Log = @()
        $Script:XamlThemeCache = $null
    }

    It 'Should read the theme once and give the same document after that' {
        $First = Get-XamlTheme -Path $Script:ThemePath
        $First.DocumentElement.LocalName | Should -Be "ResourceDictionary"
        [object]::ReferenceEquals($First, (Get-XamlTheme -Path $Script:ThemePath)) | Should -BeTrue
    }

    It 'Should read another path again rather than give the cached theme' {
        $Other = Join-Path $TestDrive "other.xaml"
        Set-Content -Path $Other -Value '<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" />'
        $null = Get-XamlTheme -Path $Script:ThemePath

        (Get-XamlTheme -Path $Other).DocumentElement.HasChildNodes | Should -BeFalse
    }

    It 'Should give nothing, logged, for a theme that cannot be read' {
        Get-XamlTheme -Path (Join-Path $TestDrive "missing.xaml") | Should -BeNullOrEmpty
        $script:Log.Message | Should -Match "could not be read"
    }
}

Describe 'Theme.xaml in every window' -Tag 'Unit' {
    BeforeAll {
        [xml]$Script:Theme = Get-Content -Path $Script:ThemePath -Raw
    }

    It 'Should give every resource a Theme. key, except the shared TabItem style' {
        foreach ($Resource in @(Get-XamlResourceElement -Container $Script:Theme.DocumentElement)) {
            $Key = Get-XamlResourceKey -Element $Resource
            if ($Key -ne "type:TabItem") {
                $Key | Should -BeLike "key:Theme.*"
            }
        }
    }

    It 'Should resolve every StaticResource in <Name> once the theme is merged' -ForEach @(
        Get-ChildItem -Path ([System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "ui")) -Filter *.xaml |
            Where-Object Name -ne "Theme.xaml" | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    ) {
        [xml]$Xaml = Get-Content -Path $Path -Raw
        $null = Merge-XamlTheme -Xaml $Xaml -Theme $Script:Theme

        $Keys = @($Xaml.SelectNodes("//*[@*[local-name()='Key']]") | ForEach-Object { $_.GetAttribute("Key", $Script:XNs) })
        $Referenced = @([regex]::Matches($Xaml.OuterXml, '\{StaticResource\s+([^\s\}]+)\}') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notlike "{x:*" } | Sort-Object -Unique)

        @($Referenced | Where-Object { $_ -notin $Keys }) | Should -BeNullOrEmpty
    }

    It 'Should leave the tab style to the theme in every window' {
        foreach ($File in Get-ChildItem -Path $Script:UiPath -Filter *.xaml | Where-Object Name -ne "Theme.xaml") {
            [xml]$Xaml = Get-Content -Path $File.FullName -Raw
            $Own = @($Xaml.SelectNodes("//*[local-name()='Style' and (@TargetType='TabItem' or @TargetType='{x:Type TabItem}')]"))
            $Own.Count | Should -Be 0 -Because "$($File.Name) should take the theme's TabItem style"
        }
    }
}
