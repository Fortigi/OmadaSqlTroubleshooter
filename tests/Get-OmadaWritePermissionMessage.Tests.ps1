#Requires -Version 7.0
# Found on a live tenant: executing a selection failed with OmadaWeb.PS's "session expired, sign in
# again" error, while executing the whole saved query worked. The account could read queries through
# OData but not write them, and Omada's OData answers a missing right with HTTP 401 - which the user was
# then told to fix by signing in again.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Get-OmadaHttpStatusCode.ps1")
    . (Join-Path $PrivatePath -ChildPath "Test-OmadaSessionExpiredError.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-OmadaWritePermissionMessage.ps1")

    $script:ODataUri = "https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING"
    $script:SessionExpiredText = "The Omada session for 'https://tenant.omada.cloud' has expired or was rejected (HTTP 401) and -NoInteractiveAuthentication was specified, so no sign-in was attempted."

    function script:New-TestErrorRecord {
        param(
            [string]$Message = "Response status code does not indicate success: 401 (Unauthorized).",
            [string]$ErrorId = "TestFailure"
        )

        return [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($Message), $ErrorId,
            [System.Management.Automation.ErrorCategory]::AuthenticationError, $null)
    }

    function script:New-Outcome {
        param(
            [string]$Method = "PUT",
            [string]$Uri = ("{0}(6129178)" -f $script:ODataUri),
            [string]$FailedStep = "TempQueryUpsert",
            [int]$CompletedSteps = 3,
            $ErrorRecord = (New-TestErrorRecord)
        )

        return @{
            FailedStep     = $FailedStep
            ErrorRecord    = $ErrorRecord
            CompletedSteps = $CompletedSteps
            Steps          = @(
                @{ Name = "GetQueryObject"; Method = "GET"; Uri = ("{0}(100)" -f $script:ODataUri) }
                @{ Name = "TempQueryProbe"; Method = "GET"; Uri = $script:ODataUri }
                @{ Name = $FailedStep; Method = $Method; Uri = $Uri }
            )
        }
    }
}

Describe "Get-OmadaWritePermissionMessage" {
    Context "A refused OData write after a successful read" {
        It "names the Update permission for a refused PUT" {
            # The reproduced case: the reused temporary object could not be updated.
            $Message = Get-OmadaWritePermissionMessage -Outcome (New-Outcome -Method "PUT")

            $Message | Should -Match "'Update' permission on the 'OData' auth element"
            $Message | Should -Match "signing in again will not help"
        }

        It "names the Create permission for a refused POST" {
            # The user's case: the first temporary object could not be created.
            $Message = Get-OmadaWritePermissionMessage -Outcome (New-Outcome -Method "POST" -Uri $script:ODataUri)

            $Message | Should -Match "'Create' permission"
        }

        It "names the Delete permission for a refused DELETE" {
            $Message = Get-OmadaWritePermissionMessage -Outcome (New-Outcome -Method "DELETE" -FailedStep "DeleteQuery")

            $Message | Should -Match "'Delete' permission"
        }

        It "names the Update permission when saving a changed query is refused" {
            $Message = Get-OmadaWritePermissionMessage -Outcome (New-Outcome -Method "PUT" -FailedStep "SaveQuery")

            $Message | Should -Match "'Update' permission"
        }

        It "recognizes OmadaWeb.PS's session-expired error, not just a raw 401" {
            # The form the error actually arrives in: OmadaWeb.PS wraps the 401 in its own error.
            $Expired = New-TestErrorRecord -Message $script:SessionExpiredText -ErrorId "OmadaSessionExpired,Invoke-OmadaRestMethod"

            Get-OmadaWritePermissionMessage -Outcome (New-Outcome -ErrorRecord $Expired) | Should -Not -BeNullOrEmpty
        }

        It "needs only one completed request as evidence that the session works" {
            Get-OmadaWritePermissionMessage -Outcome (New-Outcome -CompletedSteps 1) | Should -Not -BeNullOrEmpty
        }

        It "matches the failed step's FIRST request when a step name repeats" {
            # A multi-statement run repeats TempQueryUpsert; the first one is the one that failed.
            $Outcome = New-Outcome -Method "POST" -Uri $script:ODataUri
            $Outcome.Steps += @{ Name = "TempQueryUpsert"; Method = "PUT"; Uri = ("{0}(1)" -f $script:ODataUri) }

            Get-OmadaWritePermissionMessage -Outcome $Outcome | Should -Match "'Create' permission"
        }
    }

    Context "Anything else keeps the existing report" {
        It "returns null when no request had completed yet" {
            # Then the session may really have expired, and signing in again is the right advice.
            Get-OmadaWritePermissionMessage -Outcome (New-Outcome -CompletedSteps 0) | Should -BeNullOrEmpty
        }

        It "returns null for a refused read" {
            Get-OmadaWritePermissionMessage -Outcome (New-Outcome -Method "GET" -FailedStep "GetQueryObject") | Should -BeNullOrEmpty
        }

        It "returns null for a request that is not OData" {
            # The ASMX web services are not authorized against the OData auth element.
            $Uri = "https://tenant.omada.cloud/webservice/jQGridPopulationWebService.asmx/GetPagingData"

            Get-OmadaWritePermissionMessage -Outcome (New-Outcome -Method "POST" -Uri $Uri -FailedStep "ExecuteQuery") | Should -BeNullOrEmpty
        }

        It "returns null for a failure that is not a 401" {
            $ServerError = New-TestErrorRecord -Message "Response status code does not indicate success: 500 (Internal Server Error)."

            Get-OmadaWritePermissionMessage -Outcome (New-Outcome -ErrorRecord $ServerError) | Should -BeNullOrEmpty
        }

        It "returns null when the failed step has no recorded request" {
            # "Pipeline" is what the pipeline reports for a throw outside any request.
            $Outcome = New-Outcome
            $Outcome.FailedStep = "Pipeline"

            Get-OmadaWritePermissionMessage -Outcome $Outcome | Should -BeNullOrEmpty
        }

        It "returns null for a successful outcome or no outcome" {
            $Succeeded = New-Outcome
            $Succeeded.ErrorRecord = $null

            Get-OmadaWritePermissionMessage -Outcome $Succeeded | Should -BeNullOrEmpty
            Get-OmadaWritePermissionMessage -Outcome $null | Should -BeNullOrEmpty
        }
    }
}
