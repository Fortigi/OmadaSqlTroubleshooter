#Requires -Version 7.0
# Tests for the runspace-safe request core extracted in issue #40 (Roadmap C1).
#
# Two things are being asserted here, and the second matters more than the first:
#
#   1. The contract: success comes back as Result with a null ErrorRecord, failure as ErrorRecord
#      with a null Result, and the function never throws.
#   2. The DEPENDENCY-FREE property. This function exists to be executed in a worker runspace, which
#      has none of this module's $Script: state and none of its private functions. If someone later
#      adds a Write-LogOutput or a $Script:RunTimeData read to it, every background request starts
#      failing with a CommandNotFoundException that no unit test would otherwise catch - so the last
#      test runs the function in a genuinely empty runspace, where such an addition cannot survive.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $script:CorePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private\Invoke-OmadaRequestCore.ps1"
    . $script:CorePath

    # The single seam, steered per test.
    function Invoke-OmadaRestMethod {
        [CmdletBinding()]
        param(
            [string]$Uri,
            [string]$Method = "GET",
            $Body,
            [Parameter(ValueFromRemainingArguments = $true)]$IgnoredRest
        )
        if ($script:RestBehaviour -eq "Throw") {
            $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("transport failed"), "OmadaTransportFailure",
                [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
            $ErrorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new(
                "Resource not found for the segment 'C_P_SQLTROUBLESHOOTING'.")
            throw $ErrorRecord
        }
        if ($script:RestBehaviour -eq "Null") {
            return $null
        }
        return [PSCustomObject]@{ ReceivedUri = $Uri; ReceivedMethod = $Method; ReceivedBody = $Body }
    }

    $script:RestBehaviour = "Success"
}

Describe "Invoke-OmadaRequestCore" {
    BeforeEach {
        $script:RestBehaviour = "Success"
    }

    It "returns the response under Result with no ErrorRecord" {
        $Outcome = Invoke-OmadaRequestCore -Parameters @{ Uri = "https://tenant.omada.cloud/probe"; Method = "GET" }

        $Outcome.ErrorRecord | Should -BeNullOrEmpty
        $Outcome.Result.ReceivedUri | Should -Be "https://tenant.omada.cloud/probe"
    }

    It "splats every key of the parameter hashtable through to the transport" {
        $Outcome = Invoke-OmadaRequestCore -Parameters @{
            Uri    = "https://tenant.omada.cloud/webservice/x.asmx/GetPagingData"
            Method = "POST"
            Body   = @{ dataType = "SqlDataProducer" }
        }

        $Outcome.Result.ReceivedMethod | Should -Be "POST"
        $Outcome.Result.ReceivedBody.dataType | Should -Be "SqlDataProducer"
    }

    It "returns a null Result rather than failing when the transport returns nothing" {
        $script:RestBehaviour = "Null"

        $Outcome = Invoke-OmadaRequestCore -Parameters @{ Uri = "https://tenant.omada.cloud/probe" }

        $Outcome.Result | Should -BeNullOrEmpty
        $Outcome.ErrorRecord | Should -BeNullOrEmpty
    }

    It "returns the failure instead of throwing it" {
        $script:RestBehaviour = "Throw"

        { Invoke-OmadaRequestCore -Parameters @{ Uri = "https://tenant.omada.cloud/probe" } } | Should -Not -Throw
    }

    It "hands back an ErrorRecord that still carries what the callers classify on" {
        # Invoke-OmadaPSWebRequestWrapper branches on ErrorDetails.Message and on
        # Exception.Response.StatusCode. Losing either on the way out of the worker would silently
        # reclassify every failure as the generic "else" branch.
        $script:RestBehaviour = "Throw"

        $Outcome = Invoke-OmadaRequestCore -Parameters @{ Uri = "https://tenant.omada.cloud/probe" }

        $Outcome.Result | Should -BeNullOrEmpty
        $Outcome.ErrorRecord | Should -BeOfType [System.Management.Automation.ErrorRecord]
        $Outcome.ErrorRecord.ErrorDetails.Message | Should -Match "C_P_SQLTROUBLESHOOTING"
        $Outcome.ErrorRecord.Exception.Message | Should -Be "transport failed"
    }

    It "requires the Parameters argument" {
        # Mandatory, and asserted as metadata rather than by calling without it: a call that omits a
        # mandatory parameter prompts, which hangs an unattended run.
        (Get-Command Invoke-OmadaRequestCore).Parameters["Parameters"].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            ForEach-Object { $_.Mandatory } | Should -Contain $true
    }

    It "runs in a bare runspace that has none of this module's state or functions" {
        # The property this function exists for. The runspace below has no $Script:RunTimeData, no
        # $Script:Tracer and no Write-LogOutput - exactly like the worker that will run this for real
        # - so a dependency added to the core later fails HERE rather than in production.
        $Shell = [powershell]::Create()
        try {
            [void]$Shell.AddScript({
                    param($CorePath)
                    . $CorePath
                    function Invoke-OmadaRestMethod {
                        [CmdletBinding()]
                        param([Parameter(ValueFromRemainingArguments = $true)]$IgnoredRest)
                        return [PSCustomObject]@{ Ok = $true }
                    }
                    $Outcome = Invoke-OmadaRequestCore -Parameters @{ Uri = "https://tenant.omada.cloud/probe" }
                    return $Outcome.Result.Ok
                }).AddArgument($script:CorePath)

            $Output = $Shell.Invoke()

            # Any $Script: read or private-function call inside the core surfaces as an error stream
            # entry here, so assert the stream is empty as well as the value being right.
            $Shell.Streams.Error | Should -BeNullOrEmpty
            $Output[0] | Should -BeTrue
        }
        finally {
            $Shell.Dispose()
        }
    }
}
