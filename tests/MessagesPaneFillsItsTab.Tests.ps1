# Issue #116. The Messages pane was declared Stretch in both directions and still rendered as a small
# block in the middle of an otherwise empty tab. The declaration was never the problem: the implicit
# <Style TargetType="TextBox"> in UserControl.Resources pins Width to 300 and Height to 25 so the
# connection fields all come out the same size, and an implicit style reaches every TextBox in the
# control - including the one inside the Messages TabItem. In WPF a Width or a Height that resolves to
# a number beats HorizontalAlignment/VerticalAlignment="Stretch", and the element is centred in the
# space it declined to fill.
#
# Measured on the unfixed markup with a real WPF layout pass in an STA host, TabControl 986x586:
#   ContentPresenter 980 x 558   TextBoxQueryMessages 300 x 25 at offset 343, 291
# and with the fix in place:
#   ContentPresenter 980 x 558   TextBoxQueryMessages 980 x 558 at offset 3, 25
#
# These tests cannot repeat that measurement: the CI lane runs headless pwsh where System.Windows.*
# does not resolve, so everything here is asserted against the XAML as parsed XML instead. What they
# do guard is the property that made the measurement come out right - the pane carries an explicit
# Style, and a TextBox with an explicit Style is never given the implicit one, so no size the implicit
# style holds today or grows tomorrow can reach the pane again.

BeforeAll {
    $Script:SourceRoot = Join-Path $PSScriptRoot -ChildPath "..\src"
    $Script:TabXamlPath = Join-Path $Script:SourceRoot -ChildPath "Lib\ui\MainFormTabContent.xaml"

    [xml]$Script:TabXaml = Get-Content -Path $Script:TabXamlPath -Raw

    $Script:Namespaces = New-Object System.Xml.XmlNamespaceManager($Script:TabXaml.NameTable)
    $Script:Namespaces.AddNamespace("d", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
    $Script:Namespaces.AddNamespace("x", "http://schemas.microsoft.com/winfx/2006/xaml")

    function Get-MessagesPaneNode {
        $Script:TabXaml.DocumentElement.SelectSingleNode(
            "//d:TextBox[@*[local-name()='Name']='TextBoxQueryMessages']", $Script:Namespaces)
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
        # and it reaches whichever of the two a Setter used, because WPF also writes values in
        # element form, <Setter Property="Template"><Setter.Value>..., which this same file does
        # twice. Asking for the attribute by name can only ever mean the attribute.
        $Private:Setter = Get-StyleSetter -StyleNode $StyleNode -PropertyName $PropertyName

        if ($null -eq $Private:Setter) {
            return $null
        }

        $Private:Setter.GetAttribute("Value")
    }
}

Describe "The implicit TextBox style is still the trap it was" {
    # If these two stop being true the rest of this file is guarding nothing, and the reason the pane
    # needs an explicit style has quietly gone away. Better to be told than to keep the workaround by
    # accident.
    BeforeAll {
        $Script:ImplicitStyle = $Script:TabXaml.DocumentElement.SelectSingleNode(
            "d:UserControl.Resources/d:Style[@TargetType='TextBox'][not(@*[local-name()='Key'])]", $Script:Namespaces)
    }

    It "exists as an unkeyed style over every TextBox in the control" {
        $Script:ImplicitStyle | Should -Not -BeNullOrEmpty
    }

    It "fixes a Width and a Height, which is what overrode Stretch" {
        Get-StyleSetterValue -StyleNode $Script:ImplicitStyle -PropertyName "Width" | Should -Be "300"
        Get-StyleSetterValue -StyleNode $Script:ImplicitStyle -PropertyName "Height" | Should -Be "25"
    }
}

Describe "The Messages pane opts out of the implicit style" {
    BeforeAll {
        $Script:PaneNode = Get-MessagesPaneNode
        $Script:PaneStyleKey = "FillingTextBoxStyle"
        $Script:PaneStyle = $Script:TabXaml.DocumentElement.SelectSingleNode(
            ("d:UserControl.Resources/d:Style[@*[local-name()='Key']='{0}']" -f $Script:PaneStyleKey), $Script:Namespaces)
    }

    It "carries an explicit Style reference" {
        # This single attribute is the fix. WPF applies an implicit style only to elements whose Style
        # is unset, so naming any style here detaches the pane from the 300x25 block entirely.
        $Script:PaneNode | Should -Not -BeNullOrEmpty
        $Script:PaneNode.Style | Should -Be ("{{StaticResource {0}}}" -f $Script:PaneStyleKey)
    }

    It "resolves that reference to a style defined in the same resource dictionary" {
        # A StaticResource that does not resolve is a XamlParseException at load, which would take the
        # whole tab down rather than merely mis-sizing it.
        $Script:PaneStyle | Should -Not -BeNullOrEmpty
        $Script:PaneStyle.TargetType | Should -Be "TextBox"
    }

    It "sets no Width and no Height in that style, which is the whole point of it" {
        Get-StyleSetter -StyleNode $Script:PaneStyle -PropertyName "Width" | Should -BeNullOrEmpty
        Get-StyleSetter -StyleNode $Script:PaneStyle -PropertyName "Height" | Should -BeNullOrEmpty
        Get-StyleSetter -StyleNode $Script:PaneStyle -PropertyName "MinWidth" | Should -BeNullOrEmpty
        Get-StyleSetter -StyleNode $Script:PaneStyle -PropertyName "MinHeight" | Should -BeNullOrEmpty
    }

    It "does not derive from the implicit style either" {
        # BasedOn onto the unkeyed style would inherit the size and undo the fix while still looking
        # like an explicit style.
        $Script:PaneStyle.BasedOn | Should -BeNullOrEmpty
    }

    It "sets no Width or Height on the element itself" {
        $Script:PaneNode.Width | Should -BeNullOrEmpty
        $Script:PaneNode.Height | Should -BeNullOrEmpty
        $Script:PaneNode.MaxWidth | Should -BeNullOrEmpty
        $Script:PaneNode.MaxHeight | Should -BeNullOrEmpty
    }
}

Describe "The pane fills its tab and starts at the top left" {
    BeforeAll {
        $Script:PaneNode = Get-MessagesPaneNode
        $Script:PaneStyle = $Script:TabXaml.DocumentElement.SelectSingleNode(
            "d:UserControl.Resources/d:Style[@*[local-name()='Key']='FillingTextBoxStyle']", $Script:Namespaces)
    }

    It "still asks to stretch in both directions" {
        $Script:PaneNode.HorizontalAlignment | Should -Be "Stretch"
        $Script:PaneNode.VerticalAlignment | Should -Be "Stretch"
    }

    It "aligns its content top left rather than centred" {
        # The implicit style centred content vertically. Inherited into a full-height pane that would
        # float a two-line warning down the middle of the tab, which is the same complaint as the
        # original bug one level down.
        Get-StyleSetterValue -StyleNode $Script:PaneStyle -PropertyName "VerticalContentAlignment" | Should -Be "Top"
        Get-StyleSetterValue -StyleNode $Script:PaneStyle -PropertyName "HorizontalContentAlignment" | Should -Be "Left"
    }

    It "wraps its text and scrolls vertically when it overflows" {
        $Script:PaneNode.TextWrapping | Should -Be "Wrap"
        $Script:PaneNode.AcceptsReturn | Should -Be "True"
        $Script:PaneNode.VerticalScrollBarVisibility | Should -Be "Auto"
    }

    It "sits in a TabItem whose sibling grid is known to fill the same space" {
        # The Results grid renders full-size from the same TabControl content presenter, so the
        # presenter was never the constraint - the pane's own size was. Keeping both in one assertion
        # records why the investigation stopped at the TextBox.
        $Private:Grid = $Script:TabXaml.DocumentElement.SelectSingleNode(
            "//d:TabControl[@*[local-name()='Name']='TabControlQueryOutput']/d:TabItem[1]//d:DataGrid", $Script:Namespaces)

        $Private:Grid.HorizontalAlignment | Should -Be "Stretch"
        $Private:Grid.VerticalAlignment | Should -Be "Stretch"
    }
}

Describe "Issue #93's requirement survives the resize" {
    BeforeAll {
        $Script:PaneNode = Get-MessagesPaneNode
    }

    It "is still a read-only TextBox, so a SQL Server error stays selectable and copyable" {
        # Not negotiable, and the easiest thing to lose while rearranging the markup around it: a
        # TextBlock would fill the tab just as well and refuse to let the user copy a word of it.
        $Script:PaneNode.LocalName | Should -Be "TextBox"
        $Script:PaneNode.IsReadOnly | Should -Be "True"
        $Script:PaneNode.IsReadOnlyCaretVisible | Should -Be "True"
    }
}
