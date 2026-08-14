BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Test-TabCapacity.ps1"
    . $Command
    # The tracer preamble of the function under test redacts its bound parameters.
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\ConvertTo-RedactedLogString.ps1")
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
}

Describe 'Test-TabCapacity' {
    It 'should return true when current count is below the default capacity' {
        Test-TabCapacity -CurrentCount 0 | Should -Be $true
        Test-TabCapacity -CurrentCount 7 | Should -Be $true
    }

    It 'should return false when current count equals the default capacity' {
        Test-TabCapacity -CurrentCount 8 | Should -Be $false
    }

    It 'should return false when current count exceeds the default capacity' {
        Test-TabCapacity -CurrentCount 9 | Should -Be $false
    }

    It 'should respect a custom MaxCapacity' {
        Test-TabCapacity -CurrentCount 2 -MaxCapacity 3 | Should -Be $true
        Test-TabCapacity -CurrentCount 3 -MaxCapacity 3 | Should -Be $false
    }

    It 'should return false for a MaxCapacity of 0' {
        Test-TabCapacity -CurrentCount 0 -MaxCapacity 0 | Should -Be $false
    }
}
