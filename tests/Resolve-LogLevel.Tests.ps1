BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $FunctionPath = Join-Path $ParentPath -ChildPath "src\lib\functions\Private"
    . (Join-Path $FunctionPath -ChildPath "Resolve-LogLevel.ps1")
    # The tracer preamble of the function under test redacts its bound parameters.
    . (Join-Path $FunctionPath -ChildPath "ConvertTo-RedactedLogString.ps1")
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
}

Describe 'Resolve-LogLevel' {

    It 'lets an explicitly bound parameter win over a persisted value' {
        Resolve-LogLevel -BoundLogLevel "ERROR" -PersistedLogLevel "DEBUG" -SchemaDefault "WARNING" | Should -BeExactly "ERROR"
    }

    It 'lets an explicitly bound parameter win over the schema default when nothing is persisted' {
        Resolve-LogLevel -BoundLogLevel "ERROR" -PersistedLogLevel $null -SchemaDefault "WARNING" | Should -BeExactly "ERROR"
    }

    It 'lets a persisted value win over the schema default' {
        Resolve-LogLevel -BoundLogLevel $null -PersistedLogLevel "DEBUG" -SchemaDefault "WARNING" | Should -BeExactly "DEBUG"
    }

    It 'treats an empty bound parameter as not supplied' {
        Resolve-LogLevel -BoundLogLevel "" -PersistedLogLevel "VERBOSE" -SchemaDefault "WARNING" | Should -BeExactly "VERBOSE"
    }

    It 'treats a whitespace-only bound parameter as not supplied' {
        Resolve-LogLevel -BoundLogLevel "   " -PersistedLogLevel "VERBOSE" -SchemaDefault "WARNING" | Should -BeExactly "VERBOSE"
    }

    It 'falls back to the schema default when neither a parameter nor a persisted value is set' {
        Resolve-LogLevel -BoundLogLevel $null -PersistedLogLevel $null -SchemaDefault "WARNING" | Should -BeExactly "WARNING"
    }

    It 'falls back to the schema default when the persisted value is empty' {
        Resolve-LogLevel -BoundLogLevel $null -PersistedLogLevel "" -SchemaDefault "INFO" | Should -BeExactly "INFO"
    }

    It 'falls back to the schema default when the persisted value is unknown, instead of throwing' {
        { Resolve-LogLevel -BoundLogLevel $null -PersistedLogLevel "NOT_A_LEVEL" -SchemaDefault "WARNING" } | Should -Not -Throw
        Resolve-LogLevel -BoundLogLevel $null -PersistedLogLevel "NOT_A_LEVEL" -SchemaDefault "WARNING" | Should -BeExactly "WARNING"
    }

    It 'falls back to the schema default when the bound value is unknown, instead of throwing' {
        Resolve-LogLevel -BoundLogLevel "GIBBERISH" -PersistedLogLevel $null -SchemaDefault "WARNING" | Should -BeExactly "WARNING"
    }

    It 'prefers a valid persisted value over the schema default even when the bound value is unknown' {
        Resolve-LogLevel -BoundLogLevel "GIBBERISH" -PersistedLogLevel "DEBUG" -SchemaDefault "WARNING" | Should -BeExactly "DEBUG"
    }

    It 'normalizes the casing of a persisted value' {
        Resolve-LogLevel -BoundLogLevel $null -PersistedLogLevel "debug" -SchemaDefault "WARNING" | Should -BeExactly "DEBUG"
    }

    It 'trims surrounding whitespace from a persisted value' {
        Resolve-LogLevel -BoundLogLevel $null -PersistedLogLevel " DEBUG " -SchemaDefault "WARNING" | Should -BeExactly "DEBUG"
    }

    It 'accepts every level the log viewer offers' -ForEach @(
        @{ Level = "LOG" }
        @{ Level = "INFO" }
        @{ Level = "WARNING" }
        @{ Level = "ERROR" }
        @{ Level = "FATAL" }
        @{ Level = "DEBUG" }
        @{ Level = "VERBOSE" }
        @{ Level = "VERBOSE2" }
    ) {
        Resolve-LogLevel -BoundLogLevel $null -PersistedLogLevel $Level -SchemaDefault "WARNING" | Should -BeExactly $Level
    }

    It 'returns $null when no candidate at all is usable, instead of throwing' {
        { Resolve-LogLevel -BoundLogLevel $null -PersistedLogLevel $null -SchemaDefault $null } | Should -Not -Throw
        Resolve-LogLevel -BoundLogLevel $null -PersistedLogLevel $null -SchemaDefault $null | Should -BeNullOrEmpty
    }

    It 'always returns a string when it resolves a level' {
        Resolve-LogLevel -BoundLogLevel "DEBUG" -PersistedLogLevel $null -SchemaDefault "WARNING" | Should -BeOfType [string]
    }

    It 'declares no mandatory parameters, so a caller may omit any candidate' {
        $ParameterMetadata = (Get-Command Resolve-LogLevel).Parameters
        foreach ($ParameterName in @("BoundLogLevel", "PersistedLogLevel", "SchemaDefault")) {
            $Attribute = $ParameterMetadata[$ParameterName].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $Attribute.Mandatory | Should -Not -Contain $true -Because "$ParameterName must be optional"
        }
    }
}
