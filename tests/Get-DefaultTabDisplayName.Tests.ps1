BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-DefaultTabDisplayName.ps1"
    . $Command
    # The tracer preamble of the function under test redacts its bound parameters.
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\ConvertTo-RedactedLogString.ps1")
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
}

Describe 'Get-DefaultTabDisplayName' {
    It 'should format the injected date as SqlQuery_yyyyMMddHHmmss' {
        $Date = [datetime]::new(2026, 7, 9, 13, 5, 9)
        Get-DefaultTabDisplayName -Date $Date | Should -Be "SqlQuery_20260709130509"
    }

    It 'should zero-pad single-digit month/day/hour/minute/second components' {
        $Date = [datetime]::new(2026, 1, 2, 3, 4, 5)
        Get-DefaultTabDisplayName -Date $Date | Should -Be "SqlQuery_20260102030405"
    }

    It 'should default to the current date/time when no -Date is supplied' {
        Get-DefaultTabDisplayName | Should -Match '^SqlQuery_\d{14}$'
    }
}
