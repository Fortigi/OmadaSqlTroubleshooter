#Requires -Version 7.0
# Direct tests for Resolve-SessionLogFileBooleanSetting (issue #143): the stored value wins when it
# is a genuine boolean, the schema default fills in next, and the caller's hard fallback covers
# everything else - including a stored value that merely looks like a boolean.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Resolve-StrictBoolean.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-ConfigSchemaDefault.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-LogFileSetting.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
}

Describe "Resolve-SessionLogFileBooleanSetting" -Tag "Unit" {

    BeforeEach {
        $Script:AppGlobalConfig = $null
    }

    Context "Neither the configuration nor the schema has a usable value" {

        It "returns the caller's fallback" {
            Mock -CommandName Get-ConfigSchemaDefault -MockWith { return $null }

            Resolve-SessionLogFileBooleanSetting -Property "EnableSessionLogFile" -Fallback $true | Should -BeTrue
        }
    }

    Context "Only the schema default is usable" {

        It "uses the schema default of <SchemaValue>" -ForEach @(
            @{ SchemaValue = "true"; Expected = $true }
            @{ SchemaValue = "false"; Expected = $false }
            @{ SchemaValue = "TRUE"; Expected = $true }
        ) {
            Mock -CommandName Get-ConfigSchemaDefault -MockWith { return $SchemaValue }

            Resolve-SessionLogFileBooleanSetting -Property "EnableSessionLogFile" -Fallback $false | Should -Be $Expected
        }

        It "falls back when the schema default is empty or whitespace" {
            Mock -CommandName Get-ConfigSchemaDefault -MockWith { return "   " }

            Resolve-SessionLogFileBooleanSetting -Property "EnableSessionLogFile" -Fallback $true | Should -BeTrue
        }
    }

    Context "A stored configuration value" {

        It "wins over the schema default when it is a genuine boolean" {
            Mock -CommandName Get-ConfigSchemaDefault -MockWith { return "true" }
            $Script:AppGlobalConfig = [PSCustomObject]@{ EnableSessionLogFile = "false" }

            Resolve-SessionLogFileBooleanSetting -Property "EnableSessionLogFile" -Fallback $true | Should -BeFalse
        }

        It "accepts the integers <StoredValue> the way a bit column would carry them" -ForEach @(
            @{ StoredValue = 0; Expected = $false }
            @{ StoredValue = 1; Expected = $true }
        ) {
            Mock -CommandName Get-ConfigSchemaDefault -MockWith { return $null }
            $Script:AppGlobalConfig = [PSCustomObject]@{ EnableSessionLogFile = $StoredValue }

            Resolve-SessionLogFileBooleanSetting -Property "EnableSessionLogFile" -Fallback $true | Should -Be $Expected
        }

        It "is ignored when it is not a boolean the strict resolver can vouch for, falling back to the schema default" {
            Mock -CommandName Get-ConfigSchemaDefault -MockWith { return "true" }
            $Script:AppGlobalConfig = [PSCustomObject]@{ EnableSessionLogFile = "maybe" }

            Resolve-SessionLogFileBooleanSetting -Property "EnableSessionLogFile" -Fallback $false | Should -BeTrue
        }

        It "is ignored when it is empty or whitespace, falling back to the caller's fallback" {
            Mock -CommandName Get-ConfigSchemaDefault -MockWith { return $null }
            $Script:AppGlobalConfig = [PSCustomObject]@{ EnableSessionLogFile = "   " }

            Resolve-SessionLogFileBooleanSetting -Property "EnableSessionLogFile" -Fallback $true | Should -BeTrue
        }

        It "is ignored when it is missing from the configuration object" {
            Mock -CommandName Get-ConfigSchemaDefault -MockWith { return $null }
            $Script:AppGlobalConfig = [PSCustomObject]@{ SomeOtherProperty = "true" }

            Resolve-SessionLogFileBooleanSetting -Property "EnableSessionLogFile" -Fallback $true | Should -BeTrue
        }
    }
}
