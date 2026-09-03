#Requires -Version 7.0
# The Cancel action (issue #40).
#
# Cancel means "stop waiting", not "stop the query": Omada goes on executing it and there is no
# server-side cancellation to call (issue #43). What the app CAN be held to is everything else -
# taking the request off the queue immediately, discarding the worker's runspace, cleaning up the
# temporary object it created on the tenant, and leaving the tab usable and its previous result
# intact.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Set-TextBlockText.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-ActiveExecuteQueryRequest.ps1")
    . (Join-Path $PrivatePath -ChildPath "Stop-ExecuteQueryRequest.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:ExecuteQueryRequestDescription = "Execute query"

    $script:LogMessages = [System.Collections.Generic.List[object]]::new()
    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { $script:LogMessages.Add([pscustomobject]@{ LogType = $LogType; Message = [string]$InputObject }) }
    }

    $script:RemovedQueryObjects = [System.Collections.Generic.List[object]]::new()
    function Remove-SqlQueryObject {
        param($DoId)
        $script:RemovedQueryObjects.Add($DoId)
    }

    $script:ResetCalls = 0
    function Reset-ExecuteQueryUiState {
        param([switch]$SkipStatusBarTime)
        $script:ResetCalls++
    }

    function Get-ActiveTabSession { return $script:StubActiveTab }

    function script:Initialize-CancelTestState {
        param([switch]$WithTempObject, [switch]$WithLiveShell)

        $script:LogMessages.Clear()
        $script:RemovedQueryObjects.Clear()
        $script:ResetCalls = 0
        $script:StubActiveTab = [pscustomobject]@{ Id = "tab-A" }
        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
        $Script:MainForm = @{
            Elements = @{
                TextBlockStatusBarRows = [PSCustomObject]@{ Name = "TextBlockStatusBarRows"; Text = "2 rows" }
            }
        }

        $Shell = $null
        if ($WithLiveShell) {
            $Shell = [powershell]::Create()
            [void]$Shell.AddScript({ Start-Sleep -Seconds 30 })
            [void]$Shell.BeginInvoke()
        }

        $script:PendingItem = [pscustomobject]@{
            Description = "Execute query"
            TabSession  = [pscustomobject]@{ Id = "tab-A" }
            IsCancelled = $false
            Shell       = $Shell
            Context     = @{ Caller = @{ TempQueryDoId = $(if ($WithTempObject) { "TMP-42" } else { $null }) } }
        }
        $Script:PendingWebViewCompletions = [System.Collections.Generic.List[object]]::new()
        $Script:PendingWebViewCompletions.Add($script:PendingItem)
    }
}

Describe "Stop-ExecuteQueryRequest" {
    It "takes the request off the queue and marks it cancelled" {
        # Immediately, and before anything that can block: nothing else may treat this tab as still
        # executing while the clean-up runs, and it is what lets the button flip back in one click.
        Initialize-CancelTestState

        Stop-ExecuteQueryRequest

        $Script:PendingWebViewCompletions.Count | Should -Be 0
        $script:PendingItem.IsCancelled | Should -BeTrue
    }

    It "returns the tab to a usable state" {
        Initialize-CancelTestState

        Stop-ExecuteQueryRequest

        $script:ResetCalls | Should -Be 1
    }

    It "deletes the temporary query object the cancelled run left on the tenant" {
        # The leak this exists for: the object is created before the request and deleted by the
        # completion, so cancelling in between would strand it.
        Initialize-CancelTestState -WithTempObject

        Stop-ExecuteQueryRequest

        $script:RemovedQueryObjects | Should -Contain "TMP-42"
    }

    It "reads the temporary object id off the pending item, not from module state" {
        # It exists nowhere else by the time Cancel is clicked - the frame that created it returned
        # long ago, and the dispatching frame deliberately forgot it.
        Initialize-CancelTestState -WithTempObject
        $script:PendingItem.Context.Caller.TempQueryDoId = "TMP-99"

        Stop-ExecuteQueryRequest

        $script:RemovedQueryObjects | Should -Contain "TMP-99"
    }

    It "deletes nothing when the run created no temporary object" {
        Initialize-CancelTestState

        Stop-ExecuteQueryRequest

        $script:RemovedQueryObjects.Count | Should -Be 0
    }

    It "tells the user the query is still running on the server" {
        # The honest message. The app cannot stop an Omada query - that is issue #43 - and implying
        # otherwise would let a user start a "replacement" query believing the first had been killed.
        Initialize-CancelTestState

        Stop-ExecuteQueryRequest

        @($script:LogMessages | Where-Object { $_.Message -like "*may still be running on the server*" }).Count | Should -BeGreaterThan 0
    }

    It "marks the row count as cancelled rather than leaving a stale one" {
        Initialize-CancelTestState

        Stop-ExecuteQueryRequest

        $Script:MainForm.Elements.TextBlockStatusBarRows.Text | Should -Be "cancelled"
    }

    It "stops and disposes the worker so its runspace is not reused" {
        # A pipeline killed mid-request leaves a half-read HTTP stream and a WebRequestSession in an
        # unknown state; the pool must create a replacement rather than hand this one to the next
        # query. A disposed [powershell] refuses further use, which is what this asserts.
        Initialize-CancelTestState -WithLiveShell

        Stop-ExecuteQueryRequest

        { $script:PendingItem.Shell.AddScript({ 1 }) } | Should -Throw
    }

    It "does nothing when the tab has no query running" {
        Initialize-CancelTestState
        $Script:PendingWebViewCompletions.Clear()

        Stop-ExecuteQueryRequest

        $script:ResetCalls | Should -Be 0
        $script:RemovedQueryObjects.Count | Should -Be 0
    }

    It "still returns the tab to a usable state when the clean-up itself fails" {
        # Otherwise the user is left with a Cancel button that cancels nothing and no way back.
        Initialize-CancelTestState -WithTempObject
        function Remove-SqlQueryObject { param($DoId) throw "tenant unreachable" }

        { Stop-ExecuteQueryRequest } | Should -Not -Throw
        $script:ResetCalls | Should -BeGreaterThan 0

        function Remove-SqlQueryObject { param($DoId) $script:RemovedQueryObjects.Add($DoId) }
    }
}
