#Requires -Version 7.0
# Tests for the array-copy settings resolution of issue #103 section 5.
#
# The assertions that matter are the fallbacks. A configuration file written before these properties
# existed must behave as though the defaults were always there, and a stored value that cannot be
# used must not silently become zero - a zero ArrayCopyMaxValues would warn on every copy, and a
# misspelled ArrayCopyNullHandling must not start dropping values.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Resolve-StrictBoolean.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-ArrayCopySetting.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
    $Script:SchemaPath = Join-Path $ParentPath -ChildPath "src\Lib\schema\appGlobalConfigSchema.json"

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType = "INFO",
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { }
    }

    # The real Get-ConfigSchemaDefault reads the module's installed schema through
    # Get-ModuleBaseFolder, which does not resolve in a test session. This stand-in reads the
    # repository's own schema file instead, so the defaults under test are the ones that actually
    # ship rather than ones the test declared.
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

Describe "Get-ArrayCopySetting" {

    BeforeEach {
        $Script:AppGlobalConfig = $null
    }

    Context "The shipped schema declares every property this reads" {
        It "declares <Property>" -ForEach @(
            @{ Property = "ArrayCopyUseColumnSchema" }
            @{ Property = "ArrayCopyPowerShellTypedLiterals" }
            @{ Property = "ArrayCopyNullHandling" }
            @{ Property = "ArrayCopyMaxValues" }
        ) {
            $Definition = Get-Content $Script:SchemaPath -Raw | ConvertFrom-Json | Where-Object { $_.Name -eq $Property }
            $Definition | Should -Not -BeNullOrEmpty
        }
    }

    Context "Defaults, with nothing stored" {
        It "resolves the documented defaults" {
            $Setting = Get-ArrayCopySetting

            $Setting.UseColumnSchema | Should -BeTrue
            $Setting.PowerShellTypedLiterals | Should -BeTrue
            $Setting.NullHandling | Should -BeExactly "Emit"
            $Setting.MaxValues | Should -Be 1000
        }
    }

    Context "Stored values win" {
        It "honours a stored ArrayCopyUseColumnSchema of false" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ ArrayCopyUseColumnSchema = $false }
            (Get-ArrayCopySetting).UseColumnSchema | Should -BeFalse
        }

        It "honours a stored ArrayCopyPowerShellTypedLiterals of false" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ ArrayCopyPowerShellTypedLiterals = $false }
            (Get-ArrayCopySetting).PowerShellTypedLiterals | Should -BeFalse
        }

        It "honours a stored ArrayCopyNullHandling of Skip" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ ArrayCopyNullHandling = "Skip" }
            (Get-ArrayCopySetting).NullHandling | Should -BeExactly "Skip"
        }

        It "honours a stored ArrayCopyMaxValues" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ ArrayCopyMaxValues = 50 }
            (Get-ArrayCopySetting).MaxValues | Should -Be 50
        }
    }

    Context "Unusable stored values fall back rather than take effect" {
        It "falls back to Emit for an unrecognised ArrayCopyNullHandling" {
            # Dropping values because a setting was misspelled would make the copied list quietly
            # shorter than the selection.
            $Script:AppGlobalConfig = [PSCustomObject]@{ ArrayCopyNullHandling = "Discard" }
            (Get-ArrayCopySetting).NullHandling | Should -BeExactly "Emit"
        }

        It "falls back to the default for an ArrayCopyMaxValues of <Stored>" -ForEach @(
            @{ Stored = -1 }
            @{ Stored = 0 }
            @{ Stored = "not a number" }
        ) {
            # -1 is what Add-ConfigProperty writes for an Int with no stored value, and a zero or
            # negative threshold would warn on every single copy.
            $Script:AppGlobalConfig = [PSCustomObject]@{ ArrayCopyMaxValues = $Stored }
            (Get-ArrayCopySetting).MaxValues | Should -Be 1000
        }

        It "reads a hand-edited <Property> of `"false`" as false, not as true (review of PR #106)" -ForEach @(
            @{ Property = "ArrayCopyUseColumnSchema" }
            @{ Property = "ArrayCopyPowerShellTypedLiterals" }
        ) {
            # A configuration file is a text file people edit. "false" is a non-empty string, so a
            # plain [bool] cast reads it as $true and switches the setting ON exactly when the user
            # wrote that they wanted it off.
            $Script:AppGlobalConfig = [PSCustomObject]@{ $Property = "false" }
            $Setting = Get-ArrayCopySetting

            if ($Property -eq "ArrayCopyUseColumnSchema") {
                $Setting.UseColumnSchema | Should -BeFalse
            }
            else {
                $Setting.PowerShellTypedLiterals | Should -BeFalse
            }
        }

        It "reads a hand-edited `"true`" as true" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ ArrayCopyUseColumnSchema = "true" }
            (Get-ArrayCopySetting).UseColumnSchema | Should -BeTrue
        }

        It "ignores an unparseable boolean and keeps the schema default" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ ArrayCopyUseColumnSchema = "sometimes" }
            (Get-ArrayCopySetting).UseColumnSchema | Should -BeTrue
        }

        It "keeps the defaults when the configuration object does not exist at all" {
            $Script:AppGlobalConfig = $null
            $Setting = Get-ArrayCopySetting

            $Setting.UseColumnSchema | Should -BeTrue
            $Setting.MaxValues | Should -Be 1000
        }
    }
}
