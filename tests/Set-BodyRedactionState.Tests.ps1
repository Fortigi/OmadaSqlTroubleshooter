BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $FunctionPath = Join-Path $ParentPath -ChildPath "src\lib\functions\Private"
    . (Join-Path $FunctionPath -ChildPath "Set-BodyRedactionState.ps1")
    # The tracer preamble of the function under test redacts its bound parameters.
    . (Join-Path $FunctionPath -ChildPath "ConvertTo-RedactedLogString.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    # Records what reached the log instead of touching the real log object, so the assertions can be
    # about which lines are written rather than about how they are rendered.
    function Write-LogOutput {
        param(
            [parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
            [string]$Message,
            $ErrorObject,
            [string]$LogType = "INFO",
            [switch]$SkipDialog
        )
        process {
            $Script:LogLines.Add([PSCustomObject]@{ LogType = $LogType; Message = $Message; SkipDialog = $SkipDialog.IsPresent })
        }
    }
}

Describe 'Set-BodyRedactionState' {

    BeforeEach {
        $Script:LogLines = [System.Collections.Generic.List[object]]::new()
        $Script:SkipBodyRedaction = $false
        $Script:SkipBodyRedactionWarned = $false
        $Script:RunTimeConfig = [PSCustomObject]@{
            ApplicationName = "Test"
            Logging         = [PSCustomObject]@{ SkipBodyRedaction = $false }
        }
    }

    Context 'State' {

        It 'sets the module scope flag the redactor reads' {
            Set-BodyRedactionState -Enabled $true

            $Script:SkipBodyRedaction | Should -BeTrue
        }

        It 'clears the flag again' {
            Set-BodyRedactionState -Enabled $true
            Set-BodyRedactionState -Enabled $false

            $Script:SkipBodyRedaction | Should -BeFalse
        }

        It 'mirrors the state into the runtime configuration the rest of the application reads' {
            Set-BodyRedactionState -Enabled $true

            $Script:RunTimeConfig.Logging.SkipBodyRedaction | Should -BeTrue
        }
    }

    Context 'Warning' {

        It 'warns that query text now reaches the log and any file exported from it' {
            Set-BodyRedactionState -Enabled $true

            $Warnings = $Script:LogLines | Where-Object { $_.LogType -eq "WARNING" }
            ($Warnings | Measure-Object).Count | Should -Be 1
            $Warnings[0].Message | Should -Match "exported from it"
        }

        It 'warns without a modal dialog, which would land in front of the query being run' {
            Set-BodyRedactionState -Enabled $true

            ($Script:LogLines | Where-Object { $_.LogType -eq "WARNING" })[0].SkipDialog | Should -BeTrue
        }

        It 'warns only once per session, however often the option is toggled' {
            Set-BodyRedactionState -Enabled $true
            Set-BodyRedactionState -Enabled $false
            Set-BodyRedactionState -Enabled $true

            ($Script:LogLines | Where-Object { $_.LogType -eq "WARNING" } | Measure-Object).Count | Should -Be 1
        }

        It 'does not warn when the option is switched off' {
            Set-BodyRedactionState -Enabled $false

            $Script:LogLines | Where-Object { $_.LogType -eq "WARNING" } | Should -BeNullOrEmpty
        }
    }

    Context 'Log noise' {

        It 'writes nothing at all when the option was already off' {
            # Initialize-GlobalConfigSettings resolves this state on every start, so a line here
            # would appear in the log of every session that never touches the option.
            Set-BodyRedactionState -Enabled $false

            $Script:LogLines | Should -BeNullOrEmpty
        }

        It 'reports the option being switched off only when it was actually on' {
            Set-BodyRedactionState -Enabled $true
            $Script:LogLines.Clear()

            Set-BodyRedactionState -Enabled $false

            ($Script:LogLines | Where-Object { $_.LogType -eq "LOG" }).Message | Should -Match "disabled"
        }

        It 'reports the option being on, so the state is visible in the log' {
            Set-BodyRedactionState -Enabled $true

            ($Script:LogLines | Where-Object { $_.LogType -eq "LOG" }).Message | Should -Match "enabled"
        }
    }
}
