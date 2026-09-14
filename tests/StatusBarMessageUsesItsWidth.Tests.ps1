# Issue #118. The status bar message was cut to "Query 'MvE: Rop..." - about eighteen characters -
# in a status bar the full width of the window.
#
# The issue's own diagnosis was that the four Auto columns beside the message had no ceiling, so a
# long tenant URL and a long data connection name took what they needed and the "*" message column
# got the remainder. Measured with a real WPF layout pass in an STA host, that is not what happens.
# On the unfixed markup, at the window's own MinWidth of 1461:
#
#   column 0 arranged to 943px   TextBlockStatusBarMessage ActualWidth 100px   15 characters shown
#   column 2 = 141   column 4 = 141   column 6 = 106   column 8 = 106
#
# The message column was never starved: it had 943 of the 1461. The message block declined to use
# it. The implicit <Style TargetType="TextBlock"> in UserControl.Resources sets Width="100" for the
# form's field labels, and an implicit style reaches every TextBlock in the control - so the message
# block was pinned to exactly 100px and TextTrimming cut the text to fit that. Same trap that caught
# the Messages pane in issue #116, one element type over.
#
# The neighbours were mis-sized too, in the opposite direction: with Width=100 overridden by their
# own MinWidth=135 their columns were 141px while the TextBlocks inside rendered 491px and 428px for
# a long URL and connection name, spilling across the separators and clipping mid-character.
#
# With the fix, same 1461 window and the same text:
#
#   column 0 arranged to 760px   TextBlockStatusBarMessage ActualWidth 754px   all 81 characters
#   column 2 = 260 (URL trimmed with an ellipsis)   column 4 = 253   column 6 = 106   column 8 = 56
#
# The same harness settled the two things the ceilings could plausibly have broken. All five blocks
# arrange to Y=7.02, height 15.96, baseline 19.97 in the 30px bar - one shared baseline, 7.02px clear
# top and bottom - and the four separators sit in 5px gaps between items with no overlap. The
# ceilings clear the widest value each field can carry, in Segoe UI 12: the elapsed time is written
# by Format-ElapsedTime as hh:mm:ss.f, 53px for "00:00:02.3" and 66px even for "9999:59:59.9",
# against a 120px ceiling; the row count is "{0:n0} rows" over an [Int], so 101px at
# "2,147,483,647 rows" - which is why that ceiling is 110 and not the 90 it was first written as.
#
# These tests cannot repeat that measurement: the CI lane runs headless pwsh where System.Windows.*
# does not resolve. Everything here is asserted against the XAML as parsed XML instead, the way
# MessagesPaneFillsItsTab.Tests.ps1 does. What they guard is the property that made the measurement
# come out right - every status bar TextBlock carries an explicit Style, and a TextBlock with an
# explicit Style is never given the implicit one, so no size the implicit style holds today or grows
# tomorrow can reach the bar again - plus the ceilings that keep the neighbours off the message's
# column whatever the tenant is called.

# The bar's five items in column order, with the ceiling each one is expected to carry. The message
# is the only one with no ceiling: it is the item the remaining width belongs to.
#
# This lives at file scope, not in BeforeAll, because Pester evaluates -ForEach during discovery and
# BeforeAll does not run until afterwards - a list built there is still $null when the cases are
# expanded, and the whole Describe silently contributes no tests.
$StatusBarItems = @(
    @{ Name = "TextBlockStatusBarMessage";      Column = "0"; MinWidth = $null; MaxWidth = $null }
    @{ Name = "TextBlockStatusBarUrl";          Column = "2"; MinWidth = "135"; MaxWidth = "260" }
    @{ Name = "TextBlockStatusBarDatabaseName"; Column = "4"; MinWidth = "135"; MaxWidth = "260" }
    @{ Name = "TextBlockStatusBarQueryTime";    Column = "6"; MinWidth = "100"; MaxWidth = "120" }
    @{ Name = "TextBlockStatusBarRows";         Column = "8"; MinWidth = "50";  MaxWidth = "110" }
)

$CappedStatusBarItems = $StatusBarItems | Where-Object { $null -ne $PSItem.MaxWidth }

BeforeAll {
    $Script:SourceRoot = Join-Path $PSScriptRoot -ChildPath "..\src"
    $Script:TabXamlPath = Join-Path $Script:SourceRoot -ChildPath "Lib\ui\MainFormTabContent.xaml"

    [xml]$Script:TabXaml = Get-Content -Path $Script:TabXamlPath -Raw

    $Script:Namespaces = New-Object System.Xml.XmlNamespaceManager($Script:TabXaml.NameTable)
    $Script:Namespaces.AddNamespace("d", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
    $Script:Namespaces.AddNamespace("x", "http://schemas.microsoft.com/winfx/2006/xaml")

    $Script:StatusBarStyleKey = "StatusBarTextStyle"

    # The narrowest the window is allowed to get, and therefore the tightest the bar ever has to
    # lay itself out for in the running app.
    [xml]$Script:MainFormXaml = Get-Content -Path (Join-Path $Script:SourceRoot -ChildPath "Lib\ui\MainForm.xaml") -Raw

    $Script:MainFormNamespaces = New-Object System.Xml.XmlNamespaceManager($Script:MainFormXaml.NameTable)
    $Script:MainFormNamespaces.AddNamespace("d", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")

    $Script:WindowMinWidth = $Script:MainFormXaml.DocumentElement.SelectSingleNode(
        "d:Window.Style/d:Style/d:Setter[@Property='MinWidth']", $Script:MainFormNamespaces).GetAttribute("Value")

    function Get-StatusBarNode {
        $Script:TabXaml.DocumentElement.SelectSingleNode("//d:StatusBar", $Script:Namespaces)
    }

    function Get-StatusBarTextBlock {
        param([string] $ElementName)

        Get-StatusBarNode | ForEach-Object {
            $PSItem.SelectSingleNode(
                ("d:StatusBarItem/d:TextBlock[@*[local-name()='Name']='{0}']" -f $ElementName), $Script:Namespaces)
        }
    }

    function Get-StatusBarColumnDefinition {
        param([int] $Index)

        $Private:Columns = Get-StatusBarNode | ForEach-Object {
            $PSItem.SelectNodes(
                "d:StatusBar.ItemsPanel/d:ItemsPanelTemplate/d:Grid/d:Grid.ColumnDefinitions/d:ColumnDefinition",
                $Script:Namespaces)
        }

        $Private:Columns[$Index]
    }

    function Get-StyleSetter {
        param(
            [System.Xml.XmlNode] $StyleNode,
            [string] $PropertyName
        )

        $StyleNode.SelectSingleNode(("d:Setter[@Property='{0}']" -f $PropertyName), $Script:Namespaces)
    }

    function Get-StyleSetterValue {
        param(
            [System.Xml.XmlNode] $StyleNode,
            [string] $PropertyName
        )

        # GetAttribute rather than the adapted .Value property. On an XmlElement the underlying
        # XmlNode.Value is null and only PowerShell's adapter makes ".Value" reach the attribute -
        # and this file writes Setter values in both attribute and <Setter.Value> element form, so
        # ".Value" is not reliable here. Asking for the attribute by name can only mean the attribute.
        $Private:Setter = Get-StyleSetter -StyleNode $StyleNode -PropertyName $PropertyName

        if ($null -eq $Private:Setter) {
            return $null
        }

        $Private:Setter.GetAttribute("Value")
    }
}

Describe "The implicit TextBlock style is still the trap it was" {
    # This is the actual cause of issue #118. If it stops being true, the explicit style below is
    # guarding nothing and somebody should be told rather than left to discover it.
    BeforeAll {
        $Script:ImplicitTextBlockStyle = $Script:TabXaml.DocumentElement.SelectSingleNode(
            "d:UserControl.Resources/d:Style[@TargetType='TextBlock'][not(@*[local-name()='Key'])]", $Script:Namespaces)
    }

    It "exists as an unkeyed style over every TextBlock in the control" {
        $Script:ImplicitTextBlockStyle | Should -Not -BeNullOrEmpty
    }

    It "fixes a Width of 100, which is what the message block was pinned to" {
        Get-StyleSetterValue -StyleNode $Script:ImplicitTextBlockStyle -PropertyName "Width" | Should -Be "100"
    }
}

Describe "The status bar text style opts every item out of the implicit one" {
    BeforeAll {
        $Script:StatusBarStyle = $Script:TabXaml.DocumentElement.SelectSingleNode(
            ("d:UserControl.Resources/d:Style[@*[local-name()='Key']='{0}']" -f $Script:StatusBarStyleKey), $Script:Namespaces)
    }

    It "is defined in the same resource dictionary and targets TextBlock" {
        # A StaticResource that does not resolve is a XamlParseException at load, which takes the
        # whole tab down rather than merely mis-sizing the bar.
        $Script:StatusBarStyle | Should -Not -BeNullOrEmpty
        $Script:StatusBarStyle.TargetType | Should -Be "TextBlock"
    }

    It "sets no Width and no Height, which is the whole point of it" {
        Get-StyleSetter -StyleNode $Script:StatusBarStyle -PropertyName "Width" | Should -BeNullOrEmpty
        Get-StyleSetter -StyleNode $Script:StatusBarStyle -PropertyName "Height" | Should -BeNullOrEmpty
        Get-StyleSetter -StyleNode $Script:StatusBarStyle -PropertyName "MinWidth" | Should -BeNullOrEmpty
        Get-StyleSetter -StyleNode $Script:StatusBarStyle -PropertyName "MinHeight" | Should -BeNullOrEmpty
    }

    It "does not derive from the implicit style either" {
        # BasedOn onto the unkeyed style would inherit Width=100 and undo the fix while still
        # looking like an explicit style.
        $Script:StatusBarStyle.BasedOn | Should -BeNullOrEmpty
    }

    It "stretches across the column it was given rather than sitting at its desired width" {
        Get-StyleSetterValue -StyleNode $Script:StatusBarStyle -PropertyName "HorizontalAlignment" | Should -Be "Stretch"
    }

    It "trims with an ellipsis, so an overflow reads as 'there is more'" {
        # Before the fix only the message carried TextTrimming; the URL and the connection name
        # rendered past their columns and were clipped mid-character.
        Get-StyleSetterValue -StyleNode $Script:StatusBarStyle -PropertyName "TextTrimming" | Should -Be "CharacterEllipsis"
    }
}

Describe "Every item on the bar carries that style" {
    It "applies it to <Name>" -ForEach $StatusBarItems {
        # This single attribute is the fix. WPF applies an implicit style only to elements whose
        # Style is unset, so naming any style here detaches the element from Width=100 entirely.
        $Private:Node = Get-StatusBarTextBlock -ElementName $Name

        $Private:Node | Should -Not -BeNullOrEmpty
        $Private:Node.Style | Should -Be ("{{StaticResource {0}}}" -f $Script:StatusBarStyleKey)
    }

    It "sets no Width and no Height on <Name> itself" -ForEach $StatusBarItems {
        $Private:Node = Get-StatusBarTextBlock -ElementName $Name

        $Private:Node.Width | Should -BeNullOrEmpty
        $Private:Node.Height | Should -BeNullOrEmpty
    }

    It "stretches the containing StatusBarItem's content for <Name>" -ForEach $StatusBarItems {
        # StatusBarItem aligns its content left by default, which would leave the block at its
        # desired width inside a column that is wider than that.
        $Private:Item = Get-StatusBarNode | ForEach-Object {
            $PSItem.SelectSingleNode(
                ("d:StatusBarItem[d:TextBlock[@*[local-name()='Name']='{0}']]" -f $Name), $Script:Namespaces)
        }

        $Private:Item.HorizontalContentAlignment | Should -Be "Stretch"
    }
}

Describe "The neighbours have the ceiling Auto never gave them" {
    It "caps <Name> at <MaxWidth> so it cannot grow without limit" -ForEach $CappedStatusBarItems {
        $Private:Node = Get-StatusBarTextBlock -ElementName $Name

        $Private:Node.MaxWidth | Should -Be $MaxWidth
    }

    It "keeps <Name>'s ceiling above its floor" -ForEach $CappedStatusBarItems {
        # MaxWidth below MinWidth is not a parse error - WPF silently lets MinWidth win, and the
        # ceiling would quietly do nothing.
        $Private:Node = Get-StatusBarTextBlock -ElementName $Name

        $Private:Node.MinWidth | Should -Be $MinWidth
        [double] $Private:Node.MaxWidth | Should -BeGreaterThan ([double] $Private:Node.MinWidth)
    }

    It "leaves the message itself uncapped" {
        # The message is the item the leftover width belongs to. A MaxWidth here would reintroduce
        # the bug in a new form.
        $Private:Node = Get-StatusBarTextBlock -ElementName "TextBlockStatusBarMessage"

        $Private:Node.MaxWidth | Should -BeNullOrEmpty
        $Private:Node.MinWidth | Should -BeNullOrEmpty
    }

    It "keeps the four ceilings clear of the message's floor at the window's own minimum width" {
        # The four ceilings plus the separators between them have to leave the message column more
        # than its floor at the narrowest window the app allows, or the panel grid outgrows the bar
        # and the rightmost item falls off the edge. Both numbers are read from the markup so that
        # raising a ceiling, or the window minimum, is what makes this fail.
        $Private:Ceilings = (Get-StatusBarNode |
            ForEach-Object { $PSItem.SelectNodes("d:StatusBarItem/d:TextBlock[@MaxWidth]", $Script:Namespaces) } |
            ForEach-Object { [double] $PSItem.GetAttribute("MaxWidth") } |
            Measure-Object -Sum).Sum

        $Private:Separators = (Get-StatusBarNode |
            ForEach-Object { $PSItem.SelectNodes("d:Separator", $Script:Namespaces) } |
            ForEach-Object { [double] (Get-StatusBarColumnDefinition -Index ([int] $PSItem.GetAttribute("Grid.Column"))).Width } |
            Measure-Object -Sum).Sum

        $Private:MessageFloor = [double] (Get-StatusBarColumnDefinition -Index 0).MinWidth

        ($Private:Ceilings + $Private:Separators + $Private:MessageFloor) |
            Should -BeLessThan ([double] $Script:WindowMinWidth)
    }
}

Describe "The message column is still the one that grows" {
    It "is the only star column" {
        (Get-StatusBarColumnDefinition -Index 0).Width | Should -Be "*"
    }

    It "carries a floor so the Auto columns cannot squeeze it to nothing" {
        [double] (Get-StatusBarColumnDefinition -Index 0).MinWidth | Should -BeGreaterThan 0
    }

    It "puts the message in column 0" {
        $Private:Item = Get-StatusBarNode | ForEach-Object {
            $PSItem.SelectSingleNode(
                "d:StatusBarItem[d:TextBlock[@*[local-name()='Name']='TextBlockStatusBarMessage']]", $Script:Namespaces)
        }

        $Private:Item.GetAttribute("Grid.Column") | Should -Be "0"
    }
}

Describe "Issue #93's status bar survives the resize" {
    # Issue #118 is about how wide the columns are, not about what the bar carries. These two keep a
    # rearrangement from quietly dropping or reordering an item.
    It "still has exactly five items" {
        (Get-StatusBarNode).SelectNodes("d:StatusBarItem", $Script:Namespaces).Count | Should -Be 5
    }

    It "keeps <Name> in column <Column>" -ForEach $StatusBarItems {
        $Private:Item = Get-StatusBarNode | ForEach-Object {
            $PSItem.SelectSingleNode(
                ("d:StatusBarItem[d:TextBlock[@*[local-name()='Name']='{0}']]" -f $Name), $Script:Namespaces)
        }

        $Private:Item | Should -Not -BeNullOrEmpty
        $Private:Item.GetAttribute("Grid.Column") | Should -Be $Column
    }
}
