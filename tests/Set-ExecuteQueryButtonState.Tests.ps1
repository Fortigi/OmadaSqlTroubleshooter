#Requires -Version 7.0
# The Execute/Cancel toggle (issue #40). The button the user just pressed becomes the way to stop -
# the same pattern the Connect button already uses for Disconnect.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Set-ButtonText.ps1")
    . (Join-Path $PrivatePath -ChildPath "Set-ExecuteQueryButtonState.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $script:ExecuteGlyph = [char]0xE768
    $script:CancelGlyph = [char]0xE711

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { }
    }

    function Get-ActiveExecuteQueryRequest {
        param($TabSession)
        return $script:StubInFlightRequest
    }

    function script:Initialize-ButtonTestState {
        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
        $script:StubInFlightRequest = $null
        $Script:MainForm = @{
            Elements = @{
                ButtonExecuteQuery      = [PSCustomObject]@{ IsEnabled = $true; ToolTip = "Execute" }
                ButtonExecuteQueryText  = [PSCustomObject]@{ Name = "ButtonExecuteQueryText"; Text = "_Execute" }
                ButtonExecuteQueryImage = [PSCustomObject]@{ Name = "ButtonExecuteQueryImage"; Text = $script:ExecuteGlyph }
            }
        }
    }
}

Describe "Set-ExecuteQueryButtonState" {
    BeforeEach { Initialize-ButtonTestState }

    Context "while a query is in flight" {
        BeforeEach {
            $script:StubInFlightRequest = [pscustomobject]@{ Description = "Execute query" }
        }

        It "labels the button Cancel" {
            Set-ExecuteQueryButtonState

            $Script:MainForm.Elements.ButtonExecuteQueryText.Text | Should -Be "_Cancel"
        }

        It "keeps the button enabled, because it is the only way out" {
            # The rest of the query controls are disabled during an execute. This one must not be:
            # a disabled Cancel button would leave the user with no way to abandon the wait.
            $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $false

            Set-ExecuteQueryButtonState

            $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled | Should -BeTrue
        }

        It "says in the tooltip that the query keeps running on the server" {
            # The app cannot cancel an Omada query (issue #43). Claiming it could would let a user
            # start a replacement believing the first had been killed.
            Set-ExecuteQueryButtonState

            $Script:MainForm.Elements.ButtonExecuteQuery.ToolTip | Should -Match "keeps running on the server"
        }

        It "swaps the glyph" {
            Set-ExecuteQueryButtonState

            $Script:MainForm.Elements.ButtonExecuteQueryImage.Text | Should -Be $script:CancelGlyph
        }
    }

    Context "when nothing is running" {
        It "returns the button to Execute" {
            $Script:MainForm.Elements.ButtonExecuteQueryText.Text = "_Cancel"
            $Script:MainForm.Elements.ButtonExecuteQueryImage.Text = $script:CancelGlyph
            $Script:MainForm.Elements.ButtonExecuteQuery.ToolTip = "Stop waiting"

            Set-ExecuteQueryButtonState

            $Script:MainForm.Elements.ButtonExecuteQueryText.Text | Should -Be "_Execute"
            $Script:MainForm.Elements.ButtonExecuteQueryImage.Text | Should -Be $script:ExecuteGlyph
            $Script:MainForm.Elements.ButtonExecuteQuery.ToolTip | Should -Be "Execute"
        }

        It "does not enable a button the connection state has disabled" {
            # A disconnected tab must not get a live Execute button just because this ran.
            $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $false

            Set-ExecuteQueryButtonState

            $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled | Should -BeFalse
        }
    }

    It "is safe to call before the UI exists" {
        # It runs from Initialize-UiComponents, which is reached during tab creation and teardown.
        $Script:MainForm = $null
        { Set-ExecuteQueryButtonState } | Should -Not -Throw

        $Script:MainForm = @{ Elements = @{} }
        { Set-ExecuteQueryButtonState } | Should -Not -Throw
    }
}
