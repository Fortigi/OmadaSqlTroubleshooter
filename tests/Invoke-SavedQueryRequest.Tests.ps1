#Requires -Version 7.0
# The wrapper reports failure three ways; a successful DELETE returns $null. One answer for all of it.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private", "Invoke-SavedQueryRequest.ps1"))

    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)]$Message, [string]$LogType) process { } }
    function Invoke-OmadaPSWebRequestWrapper { }
}

Describe 'Invoke-SavedQueryRequest' -Tag 'Unit' {
    BeforeEach {
        $Script:RunTimeData = [PSCustomObject]@{ RestMethodParam = @{ Uri = $null; Method = "GET"; Body = "old" } }
        $script:Request = @{ Method = "DELETE"; Uri = "https://t/odata/dataobjects/C_P_SQLTROUBLESHOOTING(5)"; Body = $null }
    }

    It 'Should send the request it was given' {
        Mock Invoke-OmadaPSWebRequestWrapper { [PSCustomObject]@{ Id = 5 } }

        $null = Invoke-SavedQueryRequest -Request @{ Method = "PUT"; Uri = "https://t/x"; Body = @{ NAME = "n" } }

        $Script:RunTimeData.RestMethodParam.Method | Should -Be "PUT"
        $Script:RunTimeData.RestMethodParam.Uri | Should -Be "https://t/x"
        $Script:RunTimeData.RestMethodParam.Body.NAME | Should -Be "n"
    }

    It 'Should clear a body left by an earlier request' {
        Mock Invoke-OmadaPSWebRequestWrapper { }

        $null = Invoke-SavedQueryRequest -Request $script:Request

        $Script:RunTimeData.RestMethodParam.Body | Should -BeNullOrEmpty
    }

    It 'Should treat an empty answer (204 No Content) as success' {
        Mock Invoke-OmadaPSWebRequestWrapper { }

        $Response = Invoke-SavedQueryRequest -Request $script:Request

        $Response.Succeeded | Should -BeTrue
        $Response.Result | Should -BeNullOrEmpty
        $Response.Message | Should -BeNullOrEmpty
    }

    It 'Should hand back the answer' {
        Mock Invoke-OmadaPSWebRequestWrapper { [PSCustomObject]@{ DisplayName = "Renamed" } }

        (Invoke-SavedQueryRequest -Request $script:Request).Result.DisplayName | Should -Be "Renamed"
    }

    It 'Should report a returned ErrorRecord as a failure with its message' {
        Mock Invoke-OmadaPSWebRequestWrapper { [System.Management.Automation.ErrorRecord]::new([System.Exception]::new("401 Unauthorized"), "x", "NotSpecified", $null) }

        $Response = Invoke-SavedQueryRequest -Request $script:Request

        $Response.Succeeded | Should -BeFalse
        $Response.Message | Should -Be "401 Unauthorized"
        $Response.Result | Should -BeNullOrEmpty
    }

    It 'Should report a thrown failure with its message' {
        Mock Invoke-OmadaPSWebRequestWrapper { throw "OData Endpoint not enabled" }

        $Response = Invoke-SavedQueryRequest -Request $script:Request

        $Response.Succeeded | Should -BeFalse
        $Response.Message | Should -Be "OData Endpoint not enabled"
    }
}
