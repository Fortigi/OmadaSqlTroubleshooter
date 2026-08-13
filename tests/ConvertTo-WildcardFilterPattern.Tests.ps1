BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\ConvertTo-WildcardFilterPattern.ps1"
    . $Command
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
}

Describe 'ConvertTo-WildcardFilterPattern' {
    It 'wraps a plain value in wildcards' {
        ConvertTo-WildcardFilterPattern -FilterValue "Object" | Should -Be "*Object*"
    }

    It 'trims surrounding whitespace before building the pattern' {
        ConvertTo-WildcardFilterPattern -FilterValue "  Data  " | Should -Be "*Data*"
    }

    It 'returns null for an empty value' {
        ConvertTo-WildcardFilterPattern -FilterValue "" | Should -BeNullOrEmpty
    }

    It 'returns null for a whitespace-only value' {
        ConvertTo-WildcardFilterPattern -FilterValue "   " | Should -BeNullOrEmpty
    }

    It 'returns null for a null value' {
        ConvertTo-WildcardFilterPattern -FilterValue $null | Should -BeNullOrEmpty
    }

    It 'keeps an explicit asterisk wildcard intact' {
        ConvertTo-WildcardFilterPattern -FilterValue "tbl*Type" | Should -Be "*tbl*Type*"
    }

    It 'keeps an explicit question mark wildcard intact' {
        ConvertTo-WildcardFilterPattern -FilterValue "tbl?Object" | Should -Be "*tbl?Object*"
    }

    It 'escapes bracket characters so they are not read as a character class' {
        ConvertTo-WildcardFilterPattern -FilterValue "a[b" | Should -Be '*a`[b*'
    }

    It 'matches case-insensitively' {
        "ObjectTable" -like (ConvertTo-WildcardFilterPattern -FilterValue "object") | Should -BeTrue
    }

    It 'matches a substring that spans a casing boundary' {
        "ObjectTable" -like (ConvertTo-WildcardFilterPattern -FilterValue "ctt") | Should -BeTrue
    }

    It 'does not match when the characters are not adjacent' {
        "ObjectTable" -like (ConvertTo-WildcardFilterPattern -FilterValue "tbl") | Should -BeFalse
    }
}
