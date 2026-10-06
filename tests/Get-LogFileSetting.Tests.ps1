#Requires -Version 7.0
# Tests for the session log file settings resolution of issue #121, as the maintainer revised it:
# off by default, ten sessions kept, split into parts at 5 MB, no age rule.
#
# Follows the shape Get-SqlValidationSetting and Get-ArrayCopySetting established: the stored value
# wins when it is usable, the schema default fills in for a configuration file written before these
# properties existed, and nothing silently becomes zero.

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

        if ($Script:SchemaUnreadable) {
            return $null
        }

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
        $Script:SchemaUnreadable = $false
        $Script:RunTimeConfig = [PSCustomObject]@{
            ApplicationName = "Test"
            AppDataFolder   = $Script:AppDataFolder
        }
    }

    Context "The shipped schema" {

        It "declares <Property>" -ForEach @(
            @{ Property = "EnableSessionLogFile" }
            @{ Property = "SessionLogFileDirectory" }
            @{ Property = "SessionLogFileRetentionCount" }
            @{ Property = "SessionLogFileMaxSizeMegabytes" }
        ) {
            $Definition = Get-Content $Script:SchemaPath -Raw | ConvertFrom-Json | Where-Object { $_.Name -eq $Property }
            $Definition | Should -Not -BeNullOrEmpty
        }

        It "no longer declares an age rule" {
            Get-Content $Script:SchemaPath -Raw | ConvertFrom-Json | Where-Object { $_.Name -eq "SessionLogFileRetentionDays" } | Should -BeNullOrEmpty
        }

        It "no longer declares a log level of its own (issue #157)" {
            # Retired: the file follows the application's level. Leaving it in the schema would put it
            # back in every new configuration file and invite someone to set it.
            Get-Content $Script:SchemaPath -Raw | ConvertFrom-Json | Where-Object { $_.Name -eq "SessionLogFileLogLevel" } | Should -BeNullOrEmpty
        }
    }

    Context "Defaults, with nothing stored" {

        It "is off by default: a file on disk is opt-in" {
            (Get-LogFileSetting).Enabled | Should -BeFalse
        }

        It "resolves the documented retention and split size" {
            $Setting = Get-LogFileSetting

            $Setting.RetentionCount | Should -Be 10
            $Setting.MaxSizeMegabytes | Should -Be 5
        }

        It "resolves no level at all (issue #157)" {
            # The file follows the application's level, which Write-SessionLogFile reads live. A
            # LogLevel here would be a second copy of that decision, resolved once per session.
            (Get-LogFileSetting).PSObject.Properties.Name | Should -Not -Contain "LogLevel"
        }

        It "has no age setting to resolve" {
            (Get-LogFileSetting).PSObject.Properties.Name | Should -Not -Contain "RetentionDays"
        }

        It "puts the folder beside the application's other per-user state" {
            (Get-LogFileSetting).Directory | Should -BeExactly (Join-Path $Script:AppDataFolder -ChildPath "logs")
        }

        It "falls back to the same defaults when the schema cannot be read at all" {
            $Script:SchemaUnreadable = $true

            $Setting = Get-LogFileSetting

            $Setting.Enabled | Should -BeFalse
            $Setting.RetentionCount | Should -Be 10
            $Setting.MaxSizeMegabytes | Should -Be 5
        }
    }

    Context "Stored values win" {

        It "honours a stored EnableSessionLogFile of true" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ EnableSessionLogFile = $true }

            (Get-LogFileSetting).Enabled | Should -BeTrue
        }

        It "honours a hand-edited quoted 'false', which a plain [bool] cast would read as true" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ EnableSessionLogFile = "false" }

            (Get-LogFileSetting).Enabled | Should -BeFalse
        }

        It "honours a stored directory" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileDirectory = "D:\Logs\Omada" }

            (Get-LogFileSetting).Directory | Should -BeExactly "D:\Logs\Omada"
        }

        It "ignores a stored SessionLogFileLogLevel without error, as a config file written before #157 still has one" {
            # The acceptance criterion for retiring the setting: an existing configuration file keeps
            # the value on disk, and loading it must neither fail nor warn nor resurrect a file level.
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileLogLevel = "verbose2" }

            # Two statements, not an assignment inside Should -Not -Throw: a scriptblock handed to
            # Should runs in its own scope, so assigning there leaves this $Setting null and the
            # assertions below would read the scope rather than the function.
            { Get-LogFileSetting } | Should -Not -Throw
            $Setting = Get-LogFileSetting

            $Setting | Should -Not -BeNullOrEmpty
            $Setting.PSObject.Properties.Name | Should -Not -Contain "LogLevel"
            $Setting.RetentionCount | Should -Be 10
            $Setting.MaxSizeMegabytes | Should -Be 5
        }

        It "honours stored retention and size numbers" {
            $Script:AppGlobalConfig = [PSCustomObject]@{
                SessionLogFileRetentionCount   = 3
                SessionLogFileMaxSizeMegabytes = 1
            }

            $Setting = Get-LogFileSetting

            $Setting.RetentionCount | Should -Be 3
            $Setting.MaxSizeMegabytes | Should -Be 1
        }
    }

    Context "Unusable stored values fall back to the default rather than to zero" {

        It "ignores the -1 Add-ConfigProperty writes for an Int with no stored value" {
            $Script:AppGlobalConfig = [PSCustomObject]@{
                SessionLogFileRetentionCount   = -1
                SessionLogFileMaxSizeMegabytes = -1
            }

            $Setting = Get-LogFileSetting

            $Setting.RetentionCount | Should -Be 10
            $Setting.MaxSizeMegabytes | Should -Be 5
        }

        It "ignores a zero split size, which would split the file after every line" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileMaxSizeMegabytes = 0 }

            (Get-LogFileSetting).MaxSizeMegabytes | Should -Be 5
        }

        It "ignores an unreadable stored SessionLogFileLogLevel just as quietly" {
            # It was never read in the first place since #157, so even nonsense in that property is
            # inert. Kept as a test because "loads without error" is the criterion, not "is parsed".
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileLogLevel = "CHATTY" }

            { Get-LogFileSetting } | Should -Not -Throw
            (Get-LogFileSetting).PSObject.Properties.Name | Should -Not -Contain "LogLevel"
        }

        It "ignores an unreadable EnableSessionLogFile, leaving the file off" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ EnableSessionLogFile = "perhaps" }

            (Get-LogFileSetting).Enabled | Should -BeFalse
        }

        It "ignores a whitespace-only directory" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileDirectory = "   " }

            (Get-LogFileSetting).Directory | Should -BeExactly (Join-Path $Script:AppDataFolder -ChildPath "logs")
        }
    }
}
