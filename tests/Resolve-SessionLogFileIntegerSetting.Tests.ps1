#Requires -Version 7.0
# Direct tests for Resolve-SessionLogFileIntegerSetting (issue #143): a positive-integer setting,
# where "greater than zero" - not merely "not null" - decides whether a stored or schema value is
# usable, because Add-ConfigProperty writes -1 for an Int with no stored value.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Get-ConfigSchemaDefault.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-LogFileSetting.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
}

Describe "Resolve-SessionLogFileIntegerSetting" -Tag "Unit" {

    BeforeEach {
        $Script:AppGlobalConfig = $null
    }

    Context "Neither the configuration nor the schema has a usable value" {

        It "returns the caller's fallback" {
            Mock -CommandName Get-ConfigSchemaDefault -MockWith { return $null }

            Resolve-SessionLogFileIntegerSetting -Property "SessionLogFileRetentionCount" -Fallback 10 | Should -Be 10
        }
    }

    Context "Only the schema default is usable" {

        It "uses a positive schema default" {
            Mock -CommandName Get-ConfigSchemaDefault -MockWith { return "7" }

            Resolve-SessionLogFileIntegerSetting -Property "SessionLogFileRetentionCount" -Fallback 10 | Should -Be 7
        }

        It "falls back when the schema default is <SchemaValue>" -ForEach @(
            @{ SchemaValue = "0" }
            @{ SchemaValue = "-1" }
            @{ SchemaValue = "not a number" }
            @{ SchemaValue = "" }
        ) {
            Mock -CommandName Get-ConfigSchemaDefault -MockWith { return $SchemaValue }

            Resolve-SessionLogFileIntegerSetting -Property "SessionLogFileRetentionCount" -Fallback 10 | Should -Be 10
        }
    }

    Context "A stored configuration value" {

        It "wins over the schema default when it is a positive integer" {
            Mock -CommandName Get-ConfigSchemaDefault -MockWith { return "7" }
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileRetentionCount = 25 }

            Resolve-SessionLogFileIntegerSetting -Property "SessionLogFileRetentionCount" -Fallback 10 | Should -Be 25
        }

        It "accepts a positive value stored as a string" {
            Mock -CommandName Get-ConfigSchemaDefault -MockWith { return $null }
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileRetentionCount = "3" }

            Resolve-SessionLogFileIntegerSetting -Property "SessionLogFileRetentionCount" -Fallback 10 | Should -Be 3
        }

        It "is ignored when it is <StoredValue>, falling back to the schema default" -ForEach @(
            @{ StoredValue = 0 }
            @{ StoredValue = -1 }
            @{ StoredValue = "not a number" }
            @{ StoredValue = "" }
        ) {
            Mock -CommandName Get-ConfigSchemaDefault -MockWith { return "7" }
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileRetentionCount = $StoredValue }

            Resolve-SessionLogFileIntegerSetting -Property "SessionLogFileRetentionCount" -Fallback 10 | Should -Be 7
        }

        It "is ignored when it is missing from the configuration object" {
            Mock -CommandName Get-ConfigSchemaDefault -MockWith { return $null }
            $Script:AppGlobalConfig = [PSCustomObject]@{ SomeOtherProperty = 99 }

            Resolve-SessionLogFileIntegerSetting -Property "SessionLogFileRetentionCount" -Fallback 10 | Should -Be 10
        }
    }
}
