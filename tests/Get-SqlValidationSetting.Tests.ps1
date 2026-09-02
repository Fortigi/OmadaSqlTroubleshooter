#Requires -Version 7.0
# Tests for the configuration and the graceful-degradation switch of the client-side T-SQL syntax
# pass (issue #61, acceptance criteria 6 and 7).

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    $Script:SchemaPath = Join-Path $ParentPath -ChildPath "src\Lib\schema\appGlobalConfigSchema.json"

    . (Join-Path $PrivatePath -ChildPath "Get-SqlValidationSetting.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType = "INFO",
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { }
    }

    # The real Get-ConfigSchemaDefault reads the module's own schema through Get-ModuleBaseFolder,
    # which needs a running application. Reading the same file directly keeps the schema - not a
    # duplicated literal - as the source of truth for the defaults asserted here.
    $Script:SchemaProperty = Get-Content -Path $Script:SchemaPath -Raw | ConvertFrom-Json

    function Get-ConfigSchemaDefault {
        param([string]$Property, [string]$SchemaPath)

        return ($Script:SchemaProperty | Where-Object { $_.Name -eq $Property } | Select-Object -First 1).DefaultValue
    }
}

Describe 'Global configuration schema' -Tag 'Unit' {

    It 'Should declare <Name> as <Type> with a default of <Default>' -ForEach @(
        @{ Name = 'EnableSyntaxValidation'; Type = 'Bool'; Default = $true }
        @{ Name = 'ValidationDebounceMilliseconds'; Type = 'Int'; Default = 400 }
        @{ Name = 'WarnOnExecuteWithErrors'; Type = 'Bool'; Default = $true }
    ) {
        $Property = $Script:SchemaProperty | Where-Object { $_.Name -eq $Name } | Select-Object -First 1

        $Property | Should -Not -BeNullOrEmpty -Because "issue #61 section 4 requires '$Name'"
        $Property.Type | Should -Be $Type
        $Property.DefaultValue | Should -Be $Default
    }

    It 'Should declare SqlParserVersion so the parser version is configurable' {
        # Open question 4: a fixed parser version against an unknown compatibility level is the main
        # false-positive risk, so the discovered default must be overridable. No default value: the
        # empty string means "use the newest parser the assembly ships".
        $Property = $Script:SchemaProperty | Where-Object { $_.Name -eq 'SqlParserVersion' } | Select-Object -First 1

        $Property | Should -Not -BeNullOrEmpty
        $Property.Type | Should -Be 'String'
    }
}

Describe 'Get-SqlValidationSetting' -Tag 'Unit' {

    BeforeEach {
        $Script:SqlSyntaxValidationAvailable = $true
        $Script:AppGlobalConfig = $null
    }

    Context 'With no stored configuration' {
        It 'Should fall back to the schema defaults' {
            $Setting = Get-SqlValidationSetting

            $Setting.Enabled | Should -BeTrue
            $Setting.DebounceMilliseconds | Should -Be 400
            $Setting.WarnOnExecuteWithErrors | Should -BeTrue
            $Setting.ParserVersion | Should -BeNullOrEmpty
        }
    }

    Context 'When the parser is unavailable' {
        # Acceptance criterion 6. The one WARNING is emitted once at startup; from here on the
        # feature is simply off, whatever the user's setting says.
        It 'Should be disabled even when the user switched validation on' {
            $Script:SqlSyntaxValidationAvailable = $false
            $Script:AppGlobalConfig = [PSCustomObject]@{ EnableSyntaxValidation = $true }

            (Get-SqlValidationSetting).Enabled | Should -BeFalse
        }

        It 'Should be disabled when availability was never resolved at all' {
            $Script:SqlSyntaxValidationAvailable = $null

            (Get-SqlValidationSetting).Enabled | Should -BeFalse
        }
    }

    Context 'When the user has switched the pass off' {
        # Acceptance criterion 7.
        It 'Should report the pass as disabled' {
            $Script:AppGlobalConfig = [PSCustomObject]@{ EnableSyntaxValidation = $false }

            (Get-SqlValidationSetting).Enabled | Should -BeFalse
        }
    }

    Context 'The debounce interval' {
        It 'Should use a stored interval of <Stored> ms' -ForEach @(
            @{ Stored = 100 }
            @{ Stored = 1500 }
        ) {
            $Script:AppGlobalConfig = [PSCustomObject]@{ ValidationDebounceMilliseconds = $Stored }

            (Get-SqlValidationSetting).DebounceMilliseconds | Should -Be $Stored
        }

        It 'Should fall back to the default for <Label>, never to zero' -ForEach @(
            @{ Label = 'the -1 an Int property gets when it has no default'; Stored = -1 }
            @{ Label = 'zero, which would mean validating on every keystroke'; Stored = 0 }
            @{ Label = 'a non-numeric value'; Stored = 'soon' }
        ) {
            $Script:AppGlobalConfig = [PSCustomObject]@{ ValidationDebounceMilliseconds = $Stored }

            (Get-SqlValidationSetting).DebounceMilliseconds | Should -Be 400
        }
    }

    Context 'The execute-time confirmation' {
        It 'Should be suppressible without switching the whole pass off' {
            $Script:AppGlobalConfig = [PSCustomObject]@{ WarnOnExecuteWithErrors = $false }

            $Setting = Get-SqlValidationSetting
            $Setting.Enabled | Should -BeTrue -Because "the squiggles stay; only the dialog goes"
            $Setting.WarnOnExecuteWithErrors | Should -BeFalse
        }
    }

    Context 'The parser version override' {
        It 'Should pass a configured parser version through' {
            $Script:AppGlobalConfig = [PSCustomObject]@{ SqlParserVersion = 'TSql160Parser' }

            (Get-SqlValidationSetting).ParserVersion | Should -Be 'TSql160Parser'
        }

        It 'Should treat a blank parser version as "newest available"' {
            $Script:AppGlobalConfig = [PSCustomObject]@{ SqlParserVersion = '  ' }

            (Get-SqlValidationSetting).ParserVersion | Should -BeNullOrEmpty
        }
    }
}
