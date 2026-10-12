#Requires -Version 7.0
# The "Parameters:" and "Result:" lines of the request wrappers, at the detail the log level asks for.
#
# Logged whole at VERBOSE, a SQL schema response was hundreds of lines naming every table in the
# customer's database, and over a second on the UI thread to build - built even when the level would
# not show it. What is asserted: VERBOSE2 gets everything, VERBOSE gets ordinary objects unchanged and
# large ones as a count, and nothing is built below VERBOSE.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Test-LogLevelThreshold.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-RedactedRequestLog.ps1")

    $script:LogMessages = [System.Collections.Generic.List[object]]::new()
    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog)
        process { $script:LogMessages.Add([pscustomobject]@{ LogType = $LogType; Message = [string]$InputObject }) }
    }

    function script:Set-TestLogLevel {
        param([string]$Level)
        $Script:RunTimeConfig = [pscustomobject]@{ ApplicationName = "Test"; Logging = [pscustomobject]@{ LogLevelSetting = $Level } }
    }

    # A schema response: one object with a property per table.
    $Private:Payload = [PSCustomObject]@{}
    for ($Private:Index = 0; $Private:Index -lt 120; $Private:Index++) {
        $Private:Payload | Add-Member -NotePropertyName ("dbo.tblSecretName{0}" -f $Private:Index) -NotePropertyValue @("Id int", "Name nvarchar(50)", "Code int", "Flag bit")
    }
    $script:SchemaResponse = [PSCustomObject]@{ d = $Private:Payload }

    $script:SmallResponse = [PSCustomObject]@{ Id = 6128075; DisplayName = "My query" }
}

Describe "Write-RedactedRequestLog" {

    BeforeEach {
        $script:LogMessages.Clear()
    }

    It "logs a large response as a count at VERBOSE, without its member names" {
        Set-TestLogLevel -Level "VERBOSE"

        Write-RedactedRequestLog -Label "Result" -InputObject $script:SchemaResponse

        $script:LogMessages.Count | Should -Be 1
        $script:LogMessages[0].LogType | Should -Be "VERBOSE"
        $script:LogMessages[0].Message | Should -BeLike "Result: *Object with 120 properties*"
        $script:LogMessages[0].Message | Should -Not -BeLike "*tblSecretName*"
    }

    It "logs an ordinary response at VERBOSE exactly as before" {
        Set-TestLogLevel -Level "VERBOSE"

        Write-RedactedRequestLog -Label "Result" -InputObject $script:SmallResponse

        $script:LogMessages[0].Message | Should -BeExactly ("Result: {0}" -f (ConvertTo-RedactedLogString -InputObject $script:SmallResponse))
    }

    It "logs the large response in full at VERBOSE2, once" {
        Set-TestLogLevel -Level "VERBOSE2"

        Write-RedactedRequestLog -Label "Result" -InputObject $script:SchemaResponse

        $script:LogMessages.Count | Should -Be 1
        $script:LogMessages[0].LogType | Should -Be "VERBOSE2"
        $script:LogMessages[0].Message | Should -BeLike "*tblSecretName0*"
    }

    It "builds nothing below VERBOSE" {
        Set-TestLogLevel -Level "DEBUG"
        Mock ConvertTo-RedactedLogString { return "built" }

        Write-RedactedRequestLog -Label "Result" -InputObject $script:SchemaResponse

        $script:LogMessages.Count | Should -Be 0
        Should -Invoke ConvertTo-RedactedLogString -Times 0 -Exactly
    }

    It "builds nothing when no log level is configured" {
        $Script:RunTimeConfig = [pscustomobject]@{ ApplicationName = "Test" }
        Mock ConvertTo-RedactedLogString { return "built" }

        Write-RedactedRequestLog -Label "Parameters" -InputObject $script:SmallResponse

        Should -Invoke ConvertTo-RedactedLogString -Times 0 -Exactly
    }

    It "still redacts at VERBOSE2" {
        Set-TestLogLevel -Level "VERBOSE2"

        Write-RedactedRequestLog -Label "Parameters" -InputObject @{ SessionKey = "do-not-log"; Uri = "https://tenant.example" }

        $script:LogMessages[0].Message | Should -Not -BeLike "*do-not-log*"
    }
}
