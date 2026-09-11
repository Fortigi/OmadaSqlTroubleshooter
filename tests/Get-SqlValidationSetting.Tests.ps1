#Requires -Version 7.0
# Tests for the configuration and the graceful-degradation switch of the three client-side validation
# passes (issue #61, acceptance criteria 6, 7, A7 and A8).

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
            [switch]$SkipDialog,
            [switch]$TabScoped
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
        @{ Name = 'EnableSchemaValidation'; Type = 'Bool'; Default = $true }
        @{ Name = 'EnableOmadaCompatibilityValidation'; Type = 'Bool'; Default = $true }
        @{ Name = 'ValidationDebounceMilliseconds'; Type = 'Int'; Default = 400 }
        @{ Name = 'WarnOnExecuteWithErrors'; Type = 'Bool'; Default = $true }
    ) {
        $Property = $Script:SchemaProperty | Where-Object { $_.Name -eq $Name } | Select-Object -First 1

        $Property | Should -Not -BeNullOrEmpty -Because "issue #61 section 4 requires '$Name'"
        $Property.Type | Should -Be $Type
        $Property.DefaultValue | Should -Be $Default
    }

    It 'Should declare OmadaCompatibilityRuleSeverity for the per-rule overrides' {
        # Issue #61 section 3.6: suppression is configuration, not a code edit. A PSObject because the
        # value is a set of rule-id/severity pairs, and Add-ConfigProperty gives an attribute-less
        # PSObject the empty object the issue specifies as its default.
        $Property = $Script:SchemaProperty | Where-Object { $_.Name -eq 'OmadaCompatibilityRuleSeverity' } | Select-Object -First 1

        $Property | Should -Not -BeNullOrEmpty
        $Property.Type | Should -Be 'PSObject'
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
            $Setting.SchemaEnabled | Should -BeTrue
            $Setting.OmadaEnabled | Should -BeTrue
            $Setting.DebounceMilliseconds | Should -Be 400
            $Setting.WarnOnExecuteWithErrors | Should -BeTrue
            $Setting.ParserVersion | Should -BeNullOrEmpty
            $Setting.RuleSeverity | Should -BeNullOrEmpty
        }
    }

    Context 'When the parser is unavailable' {
        # Acceptance criterion 6. The one WARNING is emitted once at startup; from here on the
        # feature is simply off, whatever the user's setting says.
        It 'Should disable every pass even when the user switched them all on' {
            # All three read the tree the parser produces, so without it none of them can run
            # (acceptance criteria 6 and A8).
            $Script:SqlSyntaxValidationAvailable = $false
            $Script:AppGlobalConfig = [PSCustomObject]@{
                EnableSyntaxValidation             = $true
                EnableSchemaValidation             = $true
                EnableOmadaCompatibilityValidation = $true
            }

            $Setting = Get-SqlValidationSetting
            $Setting.Enabled | Should -BeFalse
            $Setting.SchemaEnabled | Should -BeFalse
            $Setting.OmadaEnabled | Should -BeFalse
        }

        It 'Should be disabled when availability was never resolved at all' {
            $Script:SqlSyntaxValidationAvailable = $null

            (Get-SqlValidationSetting).Enabled | Should -BeFalse
        }
    }

    Context 'When the user has switched a pass off' {
        # Acceptance criteria 7 and A8: each pass switches off independently of the other two.
        It 'Should report <Property> as disabled without touching the others' -ForEach @(
            @{ Property = 'EnableSyntaxValidation'; Off = 'Enabled'; StillOn = @('SchemaEnabled', 'OmadaEnabled') }
            @{ Property = 'EnableSchemaValidation'; Off = 'SchemaEnabled'; StillOn = @('Enabled', 'OmadaEnabled') }
            @{ Property = 'EnableOmadaCompatibilityValidation'; Off = 'OmadaEnabled'; StillOn = @('Enabled', 'SchemaEnabled') }
        ) {
            $Script:AppGlobalConfig = [PSCustomObject]@{ $Property = $false }

            $Setting = Get-SqlValidationSetting
            $Setting.$Off | Should -BeFalse
            foreach ($Other in $StillOn) {
                $Setting.$Other | Should -BeTrue -Because "switching off '$Property' must not switch off '$Other'"
            }
        }
    }

    Context 'The per-rule severity overrides' {
        It 'Should pass the stored overrides through untouched' {
            # Not normalised here: Resolve-OmadaCompatibilityRuleSeverity is the one place that decides
            # what an override means, and it has each rule's own default to fall back to.
            $Script:AppGlobalConfig = [PSCustomObject]@{ OmadaCompatibilityRuleSeverity = [PSCustomObject]@{ OMD001 = 'Off' } }

            (Get-SqlValidationSetting).RuleSeverity.OMD001 | Should -Be 'Off'
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
