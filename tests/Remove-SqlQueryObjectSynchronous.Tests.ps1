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

    Context "When the tenant refuses without throwing" {
        # Invoke-OmadaPSWebRequestWrapper THROWS only for the two classified tenant failures; an
        # unclassified one comes back as an ErrorRecord. The synchronous path used to pipe that to
        # Out-Null and log a successful deletion regardless.
        BeforeEach {
            Initialize-DeleteTestState
            $script:Logged = [System.Collections.Generic.List[object]]::new()
            function Write-LogOutput {
                param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
                process { $script:Logged.Add([pscustomobject]@{ LogType = $LogType; Message = [string]$InputObject }) }
            }
            function Invoke-OmadaPSWebRequestWrapper {
                $script:SyncDeletes++
                return [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("the tenant refused"), "x",
                    [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
            }
        }

        It "does not claim the object was deleted" {
            # The damaging half: this is the cancel path, where the caller needs the TMP_<guid>
            # object gone before anything can claim its DoId. Saying it went when it did not leaves
            # the object on the tenant and the log disagreeing with reality.
            Remove-SqlQueryObject -DoId "777" -Synchronous

            ($script:Logged.Message -join " ") | Should -Not -Match "deleted successfully"
        }

        It "says the deletion failed, and says why" {
            Remove-SqlQueryObject -DoId "777" -Synchronous

            ($script:Logged.Message -join " ") | Should -Match "Failed to delete query object 777: the tenant refused"
        }

        It "reports it as a warning without a dialog, matching the asynchronous branch" {
            # A failed clean-up of a temporary object is worth recording, not worth interrupting the
            # user over - and the async completion right above already made that call.
            Remove-SqlQueryObject -DoId "777" -Synchronous

            @($script:Logged | Where-Object { $_.LogType -eq "WARNING" }).Count | Should -Be 1
        }
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
