#Requires -Version 7.0
# The race this closes, reported on #83.
#
# The temporary object is named TMP_<InstanceGuid> - one name for the whole application instance -
# and the execute pipeline PROBES for it and reuses it rather than creating a new one, so the same
# DoId comes back on every execute-selection. Remove-SqlQueryObject is fire-and-forget, so a delete
# dispatched by a cancel can land after the user has started the next execution and remove the object
# that execution is using.
#
# "Cancel, then immediately run it again" is what a user actually does, so this is the likely
# ordering rather than a remote one.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Remove-SqlQueryObject.ps1")

    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
        process { }
    }

    function ConvertTo-RedactedLogString { param($InputObject, $MaxDepth, [switch]$ShapeOnly) return "<redacted>" }
    function New-OmadaQueryRequest {
        param([string]$Kind, $Context)
        return @{ Uri = "https://tenant/odata/dataobjects/C_P_SQLTROUBLESHOOTING({0})" -f $Context.TempQueryDoId; Method = "DELETE"; Body = $null }
    }

    function script:Initialize-DeleteTestState {
        $script:AsyncDispatches = 0
        $script:SyncDeletes = 0
        $Script:Tracer = [System.Diagnostics.Trace]
        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
        $Script:AppConfig = [PSCustomObject]@{ BaseUrl = "https://tenant" }
        $Script:RunTimeData = [PSCustomObject]@{ RestMethodParam = @{} }
    }

    function Invoke-OmadaPSWebRequestWrapperAsync {
        param($Description, $Context, $OnResultScriptBlock, $PipelineContext)
        $script:AsyncDispatches++
        # A worker WAS available - the case that leaves a delete in flight.
        return [pscustomobject]@{ Description = $Description }
    }

    function Invoke-OmadaPSWebRequestWrapper { $script:SyncDeletes++ }
}

Describe "Remove-SqlQueryObject" {
    BeforeEach { Initialize-DeleteTestState }

    It "dispatches to a worker by default, because nothing waits on a clean-up" {
        Remove-SqlQueryObject -DoId "777"

        $script:AsyncDispatches | Should -Be 1
        $script:SyncDeletes | Should -Be 0
    }

    It "deletes before returning when asked to, so the DoId cannot be reused mid-flight" {
        Remove-SqlQueryObject -DoId "777" -Synchronous

        $script:SyncDeletes | Should -Be 1
    }

    It "does not dispatch at all under -Synchronous" {
        # Dispatching and then also deleting would issue the DELETE twice; and dispatching and
        # waiting would still not guarantee ordering against the next execute. The switch has to
        # skip the async path outright.
        Remove-SqlQueryObject -DoId "777" -Synchronous

        $script:AsyncDispatches | Should -Be 0
    }

    It "still reports a failure as a warning rather than throwing" {
        Mock Invoke-OmadaPSWebRequestWrapper { throw "tenant said no" }

        { Remove-SqlQueryObject -DoId "777" -Synchronous } | Should -Not -Throw
    }
}

Describe "The cancel path deletes synchronously" {
    It "asks for a synchronous delete, not a fire-and-forget one" {
        # Asserted on the source: reaching this line in Stop-ExecuteQueryRequest needs a pending
        # request, a progress bag and a live tab, and the property under test is one switch.
        $Private:Source = Get-Content -Path (Join-Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "src\Lib\Functions\Private") "Stop-ExecuteQueryRequest.ps1") -Raw

        $Private:Source | Should -Match 'Remove-SqlQueryObject\s+-DoId\s+\$Private:TempQueryDoId\s+-Synchronous'
    }
}
