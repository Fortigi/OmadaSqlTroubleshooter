#Requires -Version 7.0
# The wording Complete-ExecuteQueryPipeline reports for a failed execute. A refused OData write is
# explained as the missing permission it is; every other failure keeps its original wording.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Get-OmadaHttpStatusCode.ps1")
    . (Join-Path $PrivatePath -ChildPath "Test-OmadaSessionExpiredError.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-OmadaWritePermissionMessage.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-ExecutePipelineFailureMessage.ps1")

    function script:New-Outcome {
        param(
            [string]$Message,
            [string]$Method = "PUT",
            [int]$CompletedSteps = 3
        )

        return @{
            FailedStep     = "TempQueryUpsert"
            CompletedSteps = $CompletedSteps
            ErrorRecord    = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($Message), "TestFailure",
                [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
            Steps          = @(
                @{ Name = "TempQueryUpsert"; Method = $Method; Uri = "https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING(1)" }
            )
        }
    }
}

Describe "Get-ExecutePipelineFailureMessage" {
    It "explains a refused OData write as a missing permission and keeps the original error" {
        $Message = Get-ExecutePipelineFailureMessage -Outcome (New-Outcome -Message "Response status code does not indicate success: 401 (Unauthorized).")

        $Message | Should -Match "^Omada refused to update a SQL troubleshooting query"
        $Message | Should -Match "Details: step 'TempQueryUpsert': Response status code does not indicate success: 401 \(Unauthorized\)\.$"
    }

    It "keeps the original wording for any other failure" {
        $Message = Get-ExecutePipelineFailureMessage -Outcome (New-Outcome -Message "Response status code does not indicate success: 500 (Internal Server Error).")

        $Message | Should -Be "The query pipeline failed at step 'TempQueryUpsert': Response status code does not indicate success: 500 (Internal Server Error)."
    }

    It "keeps the original wording for a 401 before anything had completed" {
        $Message = Get-ExecutePipelineFailureMessage -Outcome (New-Outcome -Message "Response status code does not indicate success: 401 (Unauthorized)." -CompletedSteps 0)

        $Message | Should -Match "^The query pipeline failed at step 'TempQueryUpsert'"
    }
}
