#Requires -Version 7.0
# The cascade this exists to stop is not hypothetical. One HTTP 500 from the tenant produced five
# stacked error dialogs and a log entry containing four nested copies of itself, because
# Write-LogOutput -LogType ERROR ends with Write-Error and this application runs with
# $ErrorActionPreference = Stop. Every assertion below is about that: the message is reported, and
# reporting it does not unwind the caller.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Write-ContainedErrorLog.ps1")

    $script:LogMessages = [System.Collections.Generic.List[object]]::new()

    # Stands in for the real Write-LogOutput, including the part that matters: an ERROR is written
    # and THEN throws. A stub that only recorded the call would pass whatever this function did.
    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process {
            $script:LogMessages.Add([pscustomobject]@{ LogType = $LogType; Message = [string]$InputObject; ErrorObject = $ErrorObject })
            if ($LogType -eq "ERROR") {
                Write-Error -Message ([string]$InputObject) -ErrorAction Stop
            }
        }
    }
}

Describe "Write-ContainedErrorLog" {
    BeforeEach { $script:LogMessages.Clear() }

    It "reports the message at ERROR, exactly once" {
        "Response status code does not indicate success: 500" | Write-ContainedErrorLog

        $script:LogMessages.Count | Should -Be 1
        $script:LogMessages[0].LogType | Should -Be "ERROR"
        $script:LogMessages[0].Message | Should -Be "Response status code does not indicate success: 500"
    }

    It "returns normally, so the statement after it still runs" {
        # The regression in one line. The caller reported a pipeline failure and then bound the grid;
        # the report threw, so the grid was never bound and the catch reported the throw as a second
        # error, which threw again.
        $script:Reached = $false
        & {
            "boom" | Write-ContainedErrorLog
            $script:Reached = $true
        }

        $script:Reached | Should -BeTrue
    }

    It "does not rethrow even under ErrorActionPreference = Stop" {
        $ErrorActionPreference = "Stop"

        { "boom" | Write-ContainedErrorLog } | Should -Not -Throw
    }

    It "passes the originating error through for the call stack" {
        $Private:ErrorRecord = $null
        try { throw "original" } catch { $Private:ErrorRecord = $_ }

        "wrapped" | Write-ContainedErrorLog -ErrorObject $Private:ErrorRecord

        $script:LogMessages[0].ErrorObject | Should -Be $Private:ErrorRecord
    }

    It "reports every message when several are piped in" {
        @("first", "second") | Write-ContainedErrorLog

        @($script:LogMessages).Count | Should -Be 2
        $script:LogMessages[1].Message | Should -Be "second"
    }
}
