#Requires -Version 7.0
# Issue #119. Hovering the status bar did not reveal a trimmed message long enough to read it.
#
# The fix has three parts, and each one is asserted here:
#
#   The message block's ToolTip is bound to its own Text in the XAML, so it always holds the full
#   message and no code assigns it.
#
#   Whether it opens is decided at hover time. Confirm-TabStatusMessageToolTipOpening cancels the
#   opening unless Test-TabStatusMessageTrimmed says the text is trimmed at the width the block has
#   right then. Deciding when the text was written went stale: measured in an STA host against this
#   markup, the same 64-character outcome message is untrimmed at 725.87px, trimmed at 174px after a
#   resize, and untrimmed again after resizing back, all with no write.
#
#   Set-TabStatusMessage writes Text only when it changes.
#
# Measured on .NET 10.0.11 in the same host: ToolTipService.ShowDuration's registered default is
# already Int32.MaxValue, and TextBlock has no IsTextTrimmed. At a 1445px tab with both neighbouring
# columns at their ceilings the message block arranges to 725.87px and the first trim comes at about
# 134 characters, so every outcome issue #117 writes fits unless the window is narrowed.
#
# The CI lane runs headless pwsh where System.Windows.* does not resolve. The XAML is asserted as
# parsed XML and the PowerShell as plain objects standing in for the TextBlock. The stand-ins have
# no Measure method, which is the branch that lets them supply DesiredSize directly.

BeforeAll {
    $Script:SourceRoot = Join-Path $PSScriptRoot -ChildPath "..\src"

    . (Join-Path $Script:SourceRoot -ChildPath "Lib\Functions\Private\Set-TabStatusMessage.ps1")

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline)]
            $InputObject,
            $LogType
        )
    }

    function Get-ActiveTabSession {
        return $Script:TestTabSession
    }

    # A stand-in for TextBlockStatusBarMessage. Text and ToolTip are script properties so that every
    # assignment is counted, which is what "no reassignment" has to be measured by.
    function script:New-StatusBlockStub {
        param(
            [string] $Text = "Disconnected",
            [double] $ActualWidth = 0,
            [double] $NaturalWidth = 0
        )

        $Private:Stub = [pscustomobject]@{
            TextValue     = $Text
            TextWrites    = 0
            ToolTipValue  = $null
            ToolTipWrites = 0
            ActualWidth   = $ActualWidth
            DesiredSize   = [pscustomobject]@{ Width = $NaturalWidth }
        }

        $Private:Stub | Add-Member -MemberType ScriptProperty -Name Text -Value { $this.TextValue } -SecondValue {
            param($NewValue)
            $this.TextValue = $NewValue
            $this.TextWrites++
        }

        $Private:Stub | Add-Member -MemberType ScriptProperty -Name ToolTip -Value { $this.ToolTipValue } -SecondValue {
            param($NewValue)
            $this.ToolTipValue = $NewValue
            $this.ToolTipWrites++
        }

        return $Private:Stub
    }

    function script:New-ToolTipEventArgumentsStub {
        return [pscustomobject]@{ Handled = $false }
    }
}

Describe "The message block's markup" {
    BeforeAll {
        [xml]$Script:TabXaml = Get-Content -Path (Join-Path $Script:SourceRoot -ChildPath "Lib\ui\MainFormTabContent.xaml") -Raw

        $Script:Namespaces = New-Object System.Xml.XmlNamespaceManager($Script:TabXaml.NameTable)
        $Script:Namespaces.AddNamespace("d", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")

        $Script:MessageNode = $Script:TabXaml.DocumentElement.SelectSingleNode(
            "//d:StatusBar/d:StatusBarItem/d:TextBlock[@*[local-name()='Name']='TextBlockStatusBarMessage']", $Script:Namespaces)
    }

    It "exists on the status bar" {
        $Script:MessageNode | Should -Not -BeNullOrEmpty
    }

    It "binds its ToolTip to its own Text, so the tooltip always holds the full message" {
        # Whitespace is normalized so a reformat of the markup extension does not fail this; what is
        # asserted is the source (Text) and that it is read from the element itself.
        $Private:ToolTip = $Script:MessageNode.GetAttribute("ToolTip") -replace '\s+', ' '

        $Private:ToolTip | Should -Match '^\{Binding (Path=)?Text, RelativeSource=\{RelativeSource Self\}\}$'
    }

    It "keeps the tooltip open for as long as the pointer rests on it" {
        $Script:MessageNode.GetAttribute("ToolTipService.ShowDuration") | Should -Be ([string][int]::MaxValue)
    }

    It "does not declare a fixed tooltip that would repeat an untrimmed message" {
        # An element-form <TextBlock.ToolTip> would compete with the binding.
        $Script:MessageNode.SelectSingleNode("d:TextBlock.ToolTip", $Script:Namespaces) | Should -BeNullOrEmpty
    }
}

Describe "The ToolTipOpening handler is wired to the decision" {
    BeforeAll {
        $Script:HandlerPath = Join-Path $Script:SourceRoot -ChildPath "Lib\Events\MainFormTabContent.Elements.TextBlockStatusBarMessage.ps1"
    }

    It "lives where Import-EventObjects loads MainFormTabContent handlers from" {
        Test-Path -Path $Script:HandlerPath | Should -BeTrue
    }

    It "handles ToolTipOpening on the message block and delegates to Confirm-TabStatusMessageToolTipOpening with the sender" {
        $Private:Source = Get-Content -Path $Script:HandlerPath -Raw

        $Private:Source | Should -Match 'TextBlockStatusBarMessage\.Add_ToolTipOpening\('
        $Private:Source | Should -Match 'Confirm-TabStatusMessageToolTipOpening -StatusBlock \$EventSender -EventArguments \$EventArguments'
    }
}

Describe "Test-TabStatusMessageTrimmed" {
    It "says trimmed when the text needs more width than the block was given" {
        $Private:Block = New-StatusBlockStub -Text "long" -ActualWidth 174 -NaturalWidth 350.32

        Test-TabStatusMessageTrimmed -StatusBlock $Private:Block | Should -BeTrue
    }

    It "says not trimmed when the text fits" {
        $Private:Block = New-StatusBlockStub -Text "short" -ActualWidth 725.87 -NaturalWidth 350.32

        Test-TabStatusMessageTrimmed -StatusBlock $Private:Block | Should -BeFalse
    }

    It "says not trimmed when the text fits exactly" {
        $Private:Block = New-StatusBlockStub -Text "exact" -ActualWidth 350 -NaturalWidth 350

        Test-TabStatusMessageTrimmed -StatusBlock $Private:Block | Should -BeFalse
    }

    It "says not trimmed before the first layout pass, when nothing is known about the width" {
        $Private:Block = New-StatusBlockStub -Text "anything at all" -ActualWidth 0 -NaturalWidth 350

        Test-TabStatusMessageTrimmed -StatusBlock $Private:Block | Should -BeFalse
    }

    It "says not trimmed for no element at all" {
        Test-TabStatusMessageTrimmed -StatusBlock $null | Should -BeFalse
    }

    It "does not count the margin as text" {
        # DesiredSize includes Margin; ActualWidth does not.
        $Private:Block = New-StatusBlockStub -Text "fits" -ActualWidth 300 -NaturalWidth 304
        $Private:Block | Add-Member -MemberType NoteProperty -Name Margin -Value ([pscustomobject]@{ Left = 2; Right = 2 })

        Test-TabStatusMessageTrimmed -StatusBlock $Private:Block | Should -BeFalse
    }

    It "never assigns Text or ToolTip while deciding" {
        $Private:Block = New-StatusBlockStub -Text "long" -ActualWidth 174 -NaturalWidth 350

        Test-TabStatusMessageTrimmed -StatusBlock $Private:Block | Out-Null

        $Private:Block.TextWrites | Should -Be 0
        $Private:Block.ToolTipWrites | Should -Be 0
    }
}

Describe "Confirm-TabStatusMessageToolTipOpening" {
    It "lets the tooltip open when the message is trimmed" {
        $Private:Block = New-StatusBlockStub -Text "long" -ActualWidth 174 -NaturalWidth 350
        $Private:Arguments = New-ToolTipEventArgumentsStub

        Confirm-TabStatusMessageToolTipOpening -StatusBlock $Private:Block -EventArguments $Private:Arguments

        $Private:Arguments.Handled | Should -BeFalse
    }

    It "cancels the tooltip when the message fits" {
        $Private:Block = New-StatusBlockStub -Text "short" -ActualWidth 725.87 -NaturalWidth 350
        $Private:Arguments = New-ToolTipEventArgumentsStub

        Confirm-TabStatusMessageToolTipOpening -StatusBlock $Private:Block -EventArguments $Private:Arguments

        $Private:Arguments.Handled | Should -BeTrue
    }

    It "cancels the tooltip before the first layout pass" {
        $Private:Block = New-StatusBlockStub -Text "anything" -ActualWidth 0 -NaturalWidth 350
        $Private:Arguments = New-ToolTipEventArgumentsStub

        Confirm-TabStatusMessageToolTipOpening -StatusBlock $Private:Block -EventArguments $Private:Arguments

        $Private:Arguments.Handled | Should -BeTrue
    }

    It "follows a resize of the same text with no write in between" {
        # The staleness the write-time design had: narrowing the window trims a message nobody
        # rewrote, and widening it back un-trims it.
        $Private:Block = New-StatusBlockStub -Text "Query 'MvE: Rope log query' executed successfully - see Messages" -ActualWidth 725.87 -NaturalWidth 350.32
        $Private:Decisions = foreach ($Private:Width in @(725.87, 174, 725.87)) {
            $Private:Block.ActualWidth = $Private:Width
            $Private:Arguments = New-ToolTipEventArgumentsStub

            Confirm-TabStatusMessageToolTipOpening -StatusBlock $Private:Block -EventArguments $Private:Arguments

            -not $Private:Arguments.Handled
        }

        $Private:Decisions | Should -Be @($false, $true, $false)
        $Private:Block.TextWrites | Should -Be 0
        $Private:Block.ToolTipWrites | Should -Be 0
    }

    It "does not throw without event arguments" {
        $Private:Block = New-StatusBlockStub -Text "long" -ActualWidth 174 -NaturalWidth 350

        { Confirm-TabStatusMessageToolTipOpening -StatusBlock $Private:Block -EventArguments $null } | Should -Not -Throw
    }
}

Describe "Set-TabStatusMessage writes only what changed" {
    BeforeEach {
        $Script:Block = New-StatusBlockStub -Text "Connected" -ActualWidth 725.87 -NaturalWidth 60
        $Script:TestTabSession = [pscustomobject]@{
            Elements = [pscustomobject]@{ TextBlockStatusBarMessage = $Script:Block }
        }
    }

    It "does not reassign Text for an identical message" {
        Set-TabStatusMessage -Message "Connected"
        Set-TabStatusMessage -Message "Connected"

        $Script:Block.TextWrites | Should -Be 0
        $Script:Block.Text | Should -Be "Connected"
    }

    It "does not reassign Text when Reset-TabStatusMessage restores the state already shown" {
        $Script:TestTabSession | Add-Member -MemberType NoteProperty -Name ConnectionStatus -Value $true

        Reset-TabStatusMessage
        Reset-TabStatusMessage

        $Script:Block.TextWrites | Should -Be 0
    }

    It "assigns Text once for a different message" {
        Set-TabStatusMessage -Message "Query 'X' executed successfully - see Messages"

        $Script:Block.TextWrites | Should -Be 1
        $Script:Block.Text | Should -Be "Query 'X' executed successfully - see Messages"
    }

    It "treats a change of case as a change" {
        Set-TabStatusMessage -Message "connected"

        $Script:Block.TextWrites | Should -Be 1
    }

    It "never assigns ToolTip, identical write or not" {
        Set-TabStatusMessage -Message "Connected"
        Set-TabStatusMessage -Message "Query 'X' failed - see Messages"
        Set-TabStatusMessage -Message "Query 'X' failed - see Messages"

        $Script:Block.ToolTipWrites | Should -Be 0
    }
}
