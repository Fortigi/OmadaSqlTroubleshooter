#Requires -Version 7.0
# Tests for the session log file settings resolution of issue #121.
#
# Follows the shape Get-SqlValidationSetting and Get-ArrayCopySetting established: the stored value
# wins when it is usable, the schema default fills in for a configuration file written before these
# properties existed, and nothing silently becomes zero. A zero retention would delete the log the
# user is about to ask for, and a zero size ceiling would stop the file after its first line.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Resolve-StrictBoolean.ps1")
    . (Join-Path $PrivatePath -ChildPath "Resolve-LogLevel.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-LogFileSetting.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:SchemaPath = Join-Path $ParentPath -ChildPath "src\Lib\schema\appGlobalConfigSchema.json"
    $Script:AppDataFolder = Join-Path ([System.IO.Path]::GetTempPath()) -ChildPath "OmadaSqlTroubleshooterSettingTest"

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType = "INFO",
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { }
    }

    function ConvertTo-RedactedLogString {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [int]$MaxDepth = 6)
        process { return "" }
    }

    # The real Get-ConfigSchemaDefault reads the module's installed schema through
    # Get-ModuleBaseFolder, which does not resolve in a test session. This stand-in reads the
    # repository's own schema file instead, so the defaults under test are the ones that ship.
    function Get-ConfigSchemaDefault {
        param(
            [Parameter(Mandatory = $true, Position = 0)]
            [string]$Property,
            [string]$SchemaPath
        )

        $Definition = Get-Content $Script:SchemaPath -Raw | ConvertFrom-Json | Where-Object { $_.Name -eq $Property } | Select-Object -First 1
        if ($null -eq $Definition) {
            return $null
        }

        return $Definition.DefaultValue
    }
}

Describe "Get-LogFileSetting" {

    BeforeEach {
        $Script:AppGlobalConfig = $null
        $Script:RunTimeConfig = [PSCustomObject]@{
            ApplicationName = "Test"
            AppDataFolder   = $Script:AppDataFolder
        }
    }

    Context "The shipped schema declares every property this reads" {

        It "declares <Property>" -ForEach @(
            @{ Property = "EnableSessionLogFile" }
            @{ Property = "SessionLogFileLogLevel" }
            @{ Property = "SessionLogFileDirectory" }
            @{ Property = "SessionLogFileRetentionDays" }
            @{ Property = "SessionLogFileRetentionCount" }
            @{ Property = "SessionLogFileMaxSizeMegabytes" }
        ) {
            $Definition = Get-Content $Script:SchemaPath -Raw | ConvertFrom-Json | Where-Object { $_.Name -eq $Property }
            $Definition | Should -Not -BeNullOrEmpty
        }
    }

    Context "Defaults, with nothing stored" {

        It "is on by default, which is the whole point of the feature" {
            (Get-LogFileSetting).Enabled | Should -BeTrue
        }

        It "resolves the documented retention and size defaults" {
            $Setting = Get-LogFileSetting

            $Setting.LogLevel | Should -BeExactly "DEBUG"
            $Setting.RetentionDays | Should -Be 14
            $Setting.RetentionCount | Should -Be 20
            $Setting.MaxSizeMegabytes | Should -Be 20
        }

        It "puts the folder beside the application's other per-user state" {
            (Get-LogFileSetting).Directory | Should -BeExactly (Join-Path $Script:AppDataFolder -ChildPath "logs")
        }
    }

    Context "Stored values win" {

        It "honours a stored EnableSessionLogFile of false" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ EnableSessionLogFile = $false }

            (Get-LogFileSetting).Enabled | Should -BeFalse
        }

        It "honours a hand-edited quoted 'false', which a plain [bool] cast would read as true" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ EnableSessionLogFile = "false" }

            (Get-LogFileSetting).Enabled | Should -BeFalse
        }

        It "honours a stored directory" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileDirectory = "D:\Logs\Omada" }

            (Get-LogFileSetting).Directory | Should -BeExactly "D:\Logs\Omada"
        }

        It "honours a stored level, upper-cased" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileLogLevel = "verbose2" }

            (Get-LogFileSetting).LogLevel | Should -BeExactly "VERBOSE2"
        }

        It "honours stored retention and size numbers" {
            $Script:AppGlobalConfig = [PSCustomObject]@{
                SessionLogFileRetentionDays    = 3
                SessionLogFileRetentionCount   = 5
                SessionLogFileMaxSizeMegabytes = 1
            }

            $Setting = Get-LogFileSetting

            $Setting.RetentionDays | Should -Be 3
            $Setting.RetentionCount | Should -Be 5
            $Setting.MaxSizeMegabytes | Should -Be 1
        }
    }

    Context "Unusable stored values fall back to the default rather than to zero" {

        It "ignores the -1 Add-ConfigProperty writes for an Int with no stored value" {
            $Script:AppGlobalConfig = [PSCustomObject]@{
                SessionLogFileRetentionDays    = -1
                SessionLogFileRetentionCount   = -1
                SessionLogFileMaxSizeMegabytes = -1
            }

            $Setting = Get-LogFileSetting

            $Setting.RetentionDays | Should -Be 14
            $Setting.RetentionCount | Should -Be 20
            $Setting.MaxSizeMegabytes | Should -Be 20
        }

        It "ignores a zero size ceiling, which would stop the file after its first line" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileMaxSizeMegabytes = 0 }

            (Get-LogFileSetting).MaxSizeMegabytes | Should -Be 20
        }

        It "ignores a level the application does not know" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileLogLevel = "CHATTY" }

            (Get-LogFileSetting).LogLevel | Should -BeExactly "DEBUG"
        }

        It "ignores an unreadable EnableSessionLogFile rather than switching the feature off" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ EnableSessionLogFile = "perhaps" }

            (Get-LogFileSetting).Enabled | Should -BeTrue
        }

        It "ignores a whitespace-only directory" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileDirectory = "   " }

            (Get-LogFileSetting).Directory | Should -BeExactly (Join-Path $Script:AppDataFolder -ChildPath "logs")
        }
    }
}
