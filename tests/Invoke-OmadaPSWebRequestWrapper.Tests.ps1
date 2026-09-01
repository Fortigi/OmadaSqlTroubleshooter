#Requires -Version 7.0
# Regression tests for issue #65: connection state must be single-sourced.
#
# The transport used to write the status bar to "Connected" on every successful request while
# $Script:ConnectionStatus - which drives the Connect button (Test-ConnectionButton), the dropdowns
# and the Display name (Set-SqlQueryFunctionState) - stayed $false. That is how a tab ended up
# showing "Connected" in the status bar next to a "Connect" button.
#
# Note on the fixture below: the original guard tested $Script:MainForm.Definitions, a member that
# does not exist anywhere in the app (the real member is Definition), so the write was unreachable
# in practice. These tests deliberately expose BOTH spellings, backed by the same visible-window
# stub, so the assertion is "this function writes the status bar through NO spelling of that path"
# rather than "the typo is still there" - and so it fails against the pre-fix code.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Set-TextBlockText.ps1")
    . (Join-Path $PrivatePath -ChildPath "Invoke-OmadaPSWebRequestWrapper.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { }
    }

    function Suspend-WebViewCompletionPolling { }

    function Resume-WebViewCompletionPolling { }

    # The single network seam. Behaviour per test is steered by $script:RestMethodBehaviour.
    function Invoke-OmadaRestMethod {
        [CmdletBinding()]
        param(
            [Parameter(ValueFromRemainingArguments = $true)]$IgnoredRest
        )
        if ($script:RestMethodBehaviour -eq "ODataMissing") {
            $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("odata failure"), "OmadaODataMissing",
                [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
            $ErrorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new(
                "Resource not found for the segment 'C_P_SQLTROUBLESHOOTING'.")
            throw $ErrorRecord
        }
        return [PSCustomObject]@{ value = @([PSCustomObject]@{ Id = 100; DisplayName = "TestQuery" }) }
    }

    # Records how the state machine was driven, instead of touching a real WPF tree.
    $script:ConnectionStateCalls = [System.Collections.Generic.List[object]]::new()

    function Set-SqlConnectionState {
        param(
            [bool]$Status = $true
        )
        $script:ConnectionStateCalls.Add($Status)
    }

    function Initialize-WrapperTestState {
        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test"; UseWebView2Auth = $false }
        $Script:AppConfig = [PSCustomObject]@{ BaseUrl = "https://tenant.omada.cloud" }
        $Script:RunTimeData = @{
            SkipRetryRequest = $false
            RestMethodParam  = @{
                Uri                 = "https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING"
                Method              = "GET"
                Body                = $null
                AuthenticationType  = "Browser"
                ForceAuthentication = $false
            }
        }

        $StatusBarElements = @{
            TextBlockStatusBarConnectionStatus = [PSCustomObject]@{ Name = "TextBlockStatusBarConnectionStatus"; Text = "Disconnected" }
            TextBlockStatusBarDatabaseName     = [PSCustomObject]@{ Name = "TextBlockStatusBarDatabaseName"; Text = "-" }
            TextBlockStatusBarUrl              = [PSCustomObject]@{ Name = "TextBlockStatusBarUrl"; Text = "-" }
            TextBlockStatusBarQueryTime        = [PSCustomObject]@{ Name = "TextBlockStatusBarQueryTime"; Text = "00:00:00.0000000" }
        }
        # Both spellings point at the same visible window/element bag - see the note at the top.
        $VisibleWindow = [PSCustomObject]@{ IsVisible = $true }
        $StatusBarElements.Keys | ForEach-Object {
            $VisibleWindow | Add-Member -NotePropertyName $_ -NotePropertyValue $StatusBarElements[$_]
        }
        $Script:MainForm = @{
            Definition  = $VisibleWindow
            Definitions = $VisibleWindow
            Elements    = $StatusBarElements
        }

        # The tab is NOT connected: the whole point is that a successful request must not change that.
        $Script:ConnectionStatus = $false
        $script:ConnectionStateCalls.Clear()
        $script:RestMethodBehaviour = "Success"
    }
}

Describe "Invoke-OmadaPSWebRequestWrapper connection state" {
    It "returns the response of a successful request" {
        Initialize-WrapperTestState

        $Result = Invoke-OmadaPSWebRequestWrapper

        $Result.value[0].DisplayName | Should -Be "TestQuery"
    }

    It "does not flip the status bar to Connected on a successful request" {
        Initialize-WrapperTestState

        Invoke-OmadaPSWebRequestWrapper | Out-Null

        $Script:MainForm.Elements.TextBlockStatusBarConnectionStatus.Text | Should -Be "Disconnected"
        $Script:MainForm.Definition.TextBlockStatusBarConnectionStatus.Text | Should -Be "Disconnected"
    }

    It "does not change the connection flag on a successful request" {
        Initialize-WrapperTestState

        Invoke-OmadaPSWebRequestWrapper | Out-Null

        $Script:ConnectionStatus | Should -BeFalse
        $script:ConnectionStateCalls.Count | Should -Be 0
    }

    It "tears a tab down through Set-SqlConnectionState when the OData endpoint is missing" {
        Initialize-WrapperTestState
        $script:RestMethodBehaviour = "ODataMissing"

        { Invoke-OmadaPSWebRequestWrapper } | Should -Throw

        # Not four hand-written status-bar fields with the flag left untouched: one call into the
        # state machine, which updates button, status bar, dropdowns and Display name together.
        $script:ConnectionStateCalls.Count | Should -Be 1
        $script:ConnectionStateCalls[0] | Should -BeFalse
    }
}

Describe "Invoke-OmadaPSWebRequestWrapper body redaction pass-through" {

    AfterEach {
        $Script:SkipBodyRedaction = $false
    }

    It "does not pass SkipBodyRedaction to an OmadaWeb.PS that does not declare it" {
        # The pinned minimum version predates the switch, and splatting a parameter a cmdlet does
        # not have is a terminating error - so the capability check has to keep the key out.
        Initialize-WrapperTestState
        $Script:SkipBodyRedaction = $true

        # The BeforeAll mock takes only remaining arguments, standing in for an older module.
        { Invoke-OmadaPSWebRequestWrapper } | Should -Not -Throw
        $Script:RunTimeData.RestMethodParam.ContainsKey("SkipBodyRedaction") | Should -BeFalse
    }

    It "passes the current state to an OmadaWeb.PS that declares the switch" {
        Initialize-WrapperTestState
        $Script:SkipBodyRedaction = $true

        # Shadows the older mock for the duration of this test with a module that has the switch.
        function Invoke-OmadaRestMethod {
            [CmdletBinding()]
            param(
                [switch]$SkipBodyRedaction,
                [Parameter(ValueFromRemainingArguments = $true)]$IgnoredRest
            )
            $script:ReceivedSkipBodyRedaction = $SkipBodyRedaction.IsPresent
            return [PSCustomObject]@{ value = @() }
        }

        $script:ReceivedSkipBodyRedaction = $null
        Invoke-OmadaPSWebRequestWrapper | Out-Null

        $Script:RunTimeData.RestMethodParam.SkipBodyRedaction | Should -BeTrue
        $script:ReceivedSkipBodyRedaction | Should -BeTrue
    }

    It "passes the switch as off when the option is off" {
        Initialize-WrapperTestState
        $Script:SkipBodyRedaction = $false

        function Invoke-OmadaRestMethod {
            [CmdletBinding()]
            param(
                [switch]$SkipBodyRedaction,
                [Parameter(ValueFromRemainingArguments = $true)]$IgnoredRest
            )
            $script:ReceivedSkipBodyRedaction = $SkipBodyRedaction.IsPresent
            return [PSCustomObject]@{ value = @() }
        }

        $script:ReceivedSkipBodyRedaction = $null
        Invoke-OmadaPSWebRequestWrapper | Out-Null

        $Script:RunTimeData.RestMethodParam.SkipBodyRedaction | Should -BeFalse
        $script:ReceivedSkipBodyRedaction | Should -BeFalse
    }
}
