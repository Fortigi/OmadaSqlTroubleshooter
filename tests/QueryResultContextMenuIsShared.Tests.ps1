#Requires -Version 7.0
# Issue #151. The Results pane grows from one DataGrid to one grid per statement, so the context menu
# can no longer be a child of "the" grid. It moved to UserControl.Resources as a SHARED instance, and
# these tests guard the three properties that made that move safe.
#
# The reason it is shared rather than per-result is not a style preference. Initialize-UiComponents
# binds the seven menu items POSITIONALLY off ContextMenu.Items - $MenuItems[0]..[6], and [0]..[1] for
# the Copy As children - and names declared inside a DataTemplate never reach FindName at all. A menu
# inside the per-result template would therefore leave all seven commands permanently disabled, and
# nothing in the application would say why.
#
# Asserted against the XAML parsed as XML, following tests/MessagesPaneFillsItsTab.Tests.ps1: the CI
# lane runs headless pwsh where System.Windows.* does not resolve, so a real WPF load is not available
# here. What a real load would add - that the StaticResource reference resolves - is covered by the
# ordering and reference assertions below, because a key that does not match is exactly what these
# compare.

BeforeAll {
    $Script:SourceRoot = Join-Path $PSScriptRoot -ChildPath "..\src"
    $Script:TabXamlPath = Join-Path $Script:SourceRoot -ChildPath "Lib\ui\MainFormTabContent.xaml"

    [xml]$Script:TabXaml = Get-Content -Path $Script:TabXamlPath -Raw

    $Script:Namespaces = New-Object System.Xml.XmlNamespaceManager($Script:TabXaml.NameTable)
    $Script:Namespaces.AddNamespace("d", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
    $Script:Namespaces.AddNamespace("x", "http://schemas.microsoft.com/winfx/2006/xaml")

    $Script:MenuKey = "DataGridQueryResultContextMenu"

    function Get-SharedMenuNode {
        $Script:TabXaml.DocumentElement.SelectSingleNode(
            ("d:UserControl.Resources/d:ContextMenu[@*[local-name()='Key']='{0}']" -f $Script:MenuKey), $Script:Namespaces)
    }

    function Get-ResultGridNode {
        $Script:TabXaml.DocumentElement.SelectSingleNode(
            "//d:DataGrid[@*[local-name()='Name']='DataGridQueryResult']", $Script:Namespaces)
    }
}

Describe "The Results context menu is a shared resource" {

    It "is declared in UserControl.Resources under a key" {
        # A resource dictionary entry needs x:Key; x:Name would not make it addressable as a resource.
        Get-SharedMenuNode | Should -Not -BeNullOrEmpty
    }

    It "is no longer a child of any DataGrid" {
        # The whole point of the move. A DataGrid.ContextMenu child would mean one grid owns the menu
        # again, which is what cannot survive one grid per statement.
        $Private:Inline = $Script:TabXaml.DocumentElement.SelectNodes("//d:DataGrid.ContextMenu", $Script:Namespaces)

        @($Private:Inline).Count | Should -Be 0
    }

    It "is referenced by the result grid through that same key" {
        # A mismatch here is a XamlParseException at load, which takes the whole tab down rather than
        # merely losing the menu - so the reference and the key are compared rather than assumed.
        (Get-ResultGridNode).ContextMenu | Should -Be ("{{StaticResource {0}}}" -f $Script:MenuKey)
    }

    It "declares the menu before the markup that references it" {
        # StaticResource is resolved at parse time, in document order: a resource declared after its
        # use does not resolve. UserControl.Resources sits at the top of the file, which is what makes
        # this hold - stated as a test because moving the dictionary would silently break it.
        $Private:Xml = Get-Content -Path $Script:TabXamlPath -Raw
        $Private:KeyIndex = $Private:Xml.IndexOf(("x:Key=""{0}""" -f $Script:MenuKey))
        $Private:UseIndex = $Private:Xml.IndexOf(("{{StaticResource {0}}}" -f $Script:MenuKey))

        $Private:KeyIndex | Should -BeGreaterThan -1
        $Private:UseIndex | Should -BeGreaterThan -1
        $Private:KeyIndex | Should -BeLessThan $Private:UseIndex
    }
}

Describe "The menu's item order is load-bearing" {
    # Initialize-UiComponents takes these by index, not by name. Reordering the markup silently
    # repoints Copy at a different command - a change no other test in this suite would notice, and
    # one a user would discover by copying the wrong thing.

    BeforeAll {
        $Script:MenuNode = Get-SharedMenuNode
        $Script:TopLevelItem = @($Script:MenuNode.SelectNodes("d:MenuItem", $Script:Namespaces))
    }

    It "still has exactly seven top-level items" {
        # $MenuItems[0]..[6] in Initialize-UiComponents. An eighth would be bound by nothing; a
        # seventh removed would shift every index after it.
        @($Script:TopLevelItem).Count | Should -Be 7
    }

    It "keeps them in the order Initialize-UiComponents indexes them" {
        @($Script:TopLevelItem | ForEach-Object { $_.GetAttribute("Name", "http://schemas.microsoft.com/winfx/2006/xaml") }) |
            Should -Be @(
                "DataGridQueryResultMenuItemCopy"
                "DataGridQueryResultMenuItemCopyWithHeaders"
                "DataGridQueryResultMenuItemCopyAs"
                "DataGridQueryResultMenuItemSelectAll"
                "DataGridQueryResultMenuItemSaveAs"
                "DataGridQueryResultMenuItemSaveSelectedAs"
                "DataGridQueryResultMenuItemViewSelected"
            )
    }

    It "keeps the two Copy As children in their indexed order" {
        # $CopyAsMenuItems[0]/[1], read off the Copy As item rather than the menu root.
        $Private:CopyAs = $Script:TopLevelItem | Where-Object {
            $_.GetAttribute("Name", "http://schemas.microsoft.com/winfx/2006/xaml") -eq "DataGridQueryResultMenuItemCopyAs"
        }

        @($Private:CopyAs.SelectNodes("d:MenuItem", $Script:Namespaces) | ForEach-Object { $_.GetAttribute("Name", "http://schemas.microsoft.com/winfx/2006/xaml") }) |
            Should -Be @(
                "DataGridQueryResultMenuItemCopyAsSqlArray"
                "DataGridQueryResultMenuItemCopyAsPowerShellArray"
            )
    }

    It "still carries the Separator that groups copying from saving" {
        $Script:MenuNode.SelectNodes("d:Separator", $Script:Namespaces) | Should -Not -BeNullOrEmpty
    }
}

Describe "The menu kept the templates it depends on" {
    # The two keyed ControlTemplates live inside the menu's own ContextMenu.Resources, which is why the
    # move was self-contained: they travelled with it. If they were left behind, every MenuItem's
    # Template reference would fail to resolve at load.

    BeforeAll {
        $Script:MenuNode = Get-SharedMenuNode
        $Script:MenuResources = $Script:MenuNode.SelectSingleNode("d:ContextMenu.Resources", $Script:Namespaces)
    }

    It "still declares both menu-item templates alongside the menu" {
        $Script:MenuResources | Should -Not -BeNullOrEmpty

        @($Script:MenuResources.SelectNodes("d:ControlTemplate", $Script:Namespaces) |
                ForEach-Object { $_.GetAttribute("Key", "http://schemas.microsoft.com/winfx/2006/xaml") } |
                Sort-Object) |
            Should -Be @("DataGridQueryResultFlatMenuItem", "DataGridQueryResultFlatMenuItemWithSubmenu")
    }
}
