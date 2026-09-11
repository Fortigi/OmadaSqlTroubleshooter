BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Export-QueryResultFile.ps1")

    # The escaping cases below are the point of this file, so they are declared once here and
    # reused by every format: a delimiter that collides with Export-Csv's ";", an embedded
    # double quote, an embedded newline, a leading/trailing space, and non-ASCII from three
    # different scripts plus an astral-plane emoji (a surrogate pair, which is where a wrong
    # encoding shows up first).
    $Script:AwkwardRow = [PSCustomObject]@{
        Id           = 1
        WithDelim    = "alpha;beta;gamma"
        WithQuote    = 'he said "hello"'
        WithNewline  = "first`r`nsecond"
        WithTab      = "left`tright"
        WithSpaces   = "  padded  "
        NonAscii     = "Grüße, Ståle — 日本語 — Ω — 🙂"
        WithComma    = "a,b,c"
        WithApostrophe = "O'Brien"
    }

    function New-QueryResult {
        param([object[]]$Rows)
        [PSCustomObject]@{
            d = [PSCustomObject]@{
                rows = $Rows
            }
        }
    }

    function New-TestFilePath {
        param([string]$Extension)
        Join-Path ([System.IO.Path]::GetTempPath()) ("osqExport_{0}{1}" -f ([guid]::NewGuid().ToString("N")), $Extension)
    }
}

Describe 'Export-QueryResultFile' {

    Context 'JSON' {
        It 'should write a JSON file that round-trips back to the same values' {
            $Path = New-TestFilePath -Extension ".json"
            try {
                Export-QueryResultFile -QueryResult (New-QueryResult -Rows @($Script:AwkwardRow)) -Path $Path

                $Written = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
                $Row = $Written.d.rows[0]

                $Row.Id | Should -Be 1
                $Row.WithDelim | Should -Be "alpha;beta;gamma"
                $Row.WithQuote | Should -Be 'he said "hello"'
                $Row.WithNewline | Should -Be "first`r`nsecond"
                $Row.WithTab | Should -Be "left`tright"
                $Row.WithSpaces | Should -Be "  padded  "
                $Row.NonAscii | Should -Be "Grüße, Ståle — 日本語 — Ω — 🙂"
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }

        It 'should serialize deeper than ConvertTo-Json would by default' {
            # The default -Depth is 2, which would render level 4 as a type name instead of an
            # object. -Depth 15 is what makes a real Omada result (d.rows[].<nested>) survive.
            $Deep = New-QueryResult -Rows @(
                [PSCustomObject]@{
                    Level1 = [PSCustomObject]@{
                        Level2 = [PSCustomObject]@{
                            Level3 = [PSCustomObject]@{ Leaf = "reached" }
                        }
                    }
                }
            )
            $Path = New-TestFilePath -Extension ".json"
            try {
                Export-QueryResultFile -QueryResult $Deep -Path $Path
                $Written = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
                $Written.d.rows[0].Level1.Level2.Level3.Leaf | Should -Be "reached"
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }

        It 'should write JSON readable as UTF8 with the non-ASCII text intact' {
            $Path = New-TestFilePath -Extension ".json"
            try {
                Export-QueryResultFile -QueryResult (New-QueryResult -Rows @($Script:AwkwardRow)) -Path $Path
                $Bytes = [System.IO.File]::ReadAllBytes($Path)
                $Decoded = [System.Text.Encoding]::UTF8.GetString($Bytes)
                $Decoded | Should -Match "日本語"
                $Decoded | Should -Match "🙂"
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'CSV' {
        It 'should separate columns with a semicolon and write no type information line' {
            $Path = New-TestFilePath -Extension ".csv"
            try {
                Export-QueryResultFile -QueryResult (New-QueryResult -Rows @(
                        [PSCustomObject]@{ Id = 1; Name = "First" }
                        [PSCustomObject]@{ Id = 2; Name = "Second" }
                    )) -Path $Path

                $Lines = Get-Content -Path $Path -Encoding UTF8
                $Lines[0] | Should -Not -Match '^#TYPE'
                $Lines[0] | Should -Be '"Id";"Name"'
                $Lines[1] | Should -Be '"1";"First"'
                $Lines[2] | Should -Be '"2";"Second"'
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }

        It 'should keep a value containing the delimiter in a single field' {
            $Path = New-TestFilePath -Extension ".csv"
            try {
                Export-QueryResultFile -QueryResult (New-QueryResult -Rows @($Script:AwkwardRow)) -Path $Path

                $Parsed = Import-Csv -Path $Path -Delimiter ";" -Encoding UTF8
                $Parsed.WithDelim | Should -Be "alpha;beta;gamma"
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }

        It 'should double an embedded double quote and read it back unchanged' {
            $Path = New-TestFilePath -Extension ".csv"
            try {
                Export-QueryResultFile -QueryResult (New-QueryResult -Rows @($Script:AwkwardRow)) -Path $Path

                (Get-Content -Path $Path -Raw -Encoding UTF8) | Should -Match 'he said ""hello""'
                (Import-Csv -Path $Path -Delimiter ";" -Encoding UTF8).WithQuote | Should -Be 'he said "hello"'
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }

        It 'should keep an embedded newline inside one quoted field' {
            $Path = New-TestFilePath -Extension ".csv"
            try {
                Export-QueryResultFile -QueryResult (New-QueryResult -Rows @($Script:AwkwardRow)) -Path $Path

                $Parsed = Import-Csv -Path $Path -Delimiter ";" -Encoding UTF8
                @($Parsed).Count | Should -Be 1
                $Parsed.WithNewline | Should -Be "first`r`nsecond"
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }

        It 'should preserve tabs, padding spaces and non-ASCII characters' {
            $Path = New-TestFilePath -Extension ".csv"
            try {
                Export-QueryResultFile -QueryResult (New-QueryResult -Rows @($Script:AwkwardRow)) -Path $Path

                $Parsed = Import-Csv -Path $Path -Delimiter ";" -Encoding UTF8
                $Parsed.WithTab | Should -Be "left`tright"
                $Parsed.WithSpaces | Should -Be "  padded  "
                $Parsed.NonAscii | Should -Be "Grüße, Ståle — 日本語 — Ω — 🙂"
                $Parsed.WithComma | Should -Be "a,b,c"
                $Parsed.WithApostrophe | Should -Be "O'Brien"
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }

        It 'should write the columns in the order the first row declares them' {
            $Path = New-TestFilePath -Extension ".csv"
            try {
                Export-QueryResultFile -QueryResult (New-QueryResult -Rows @(
                        [PSCustomObject]@{ Zebra = "z"; Apple = "a"; Mango = "m" }
                    )) -Path $Path

                (Get-Content -Path $Path -Encoding UTF8)[0] | Should -Be '"Zebra";"Apple";"Mango"'
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }

        It 'should write a header-only file for an empty result' {
            $Path = New-TestFilePath -Extension ".csv"
            try {
                Export-QueryResultFile -QueryResult (New-QueryResult -Rows @()) -Path $Path
                Test-Path -Path $Path | Should -Be $true
                @(Import-Csv -Path $Path -Delimiter ";" -Encoding UTF8).Count | Should -Be 0
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'CLIXML' {
        It 'should round-trip the whole QueryResult wrapper, not just the rows' {
            $Path = New-TestFilePath -Extension ".xml"
            try {
                Export-QueryResultFile -QueryResult (New-QueryResult -Rows @($Script:AwkwardRow)) -Path $Path

                $Written = Import-Clixml -Path $Path
                $Written.d.rows[0].WithDelim | Should -Be "alpha;beta;gamma"
                $Written.d.rows[0].WithQuote | Should -Be 'he said "hello"'
                $Written.d.rows[0].WithNewline | Should -Be "first`r`nsecond"
                $Written.d.rows[0].NonAscii | Should -Be "Grüße, Ståle — 日本語 — Ω — 🙂"
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }

        It 'should preserve value types rather than flattening everything to a string' {
            $Path = New-TestFilePath -Extension ".xml"
            try {
                Export-QueryResultFile -QueryResult (New-QueryResult -Rows @(
                        [PSCustomObject]@{
                            Number  = 42
                            Decimal = 1.5
                            Flag    = $true
                            Moment  = [datetime]"2026-07-18T12:34:56Z"
                            Nothing = $null
                        }
                    )) -Path $Path

                $Row = (Import-Clixml -Path $Path).d.rows[0]
                $Row.Number | Should -BeOfType [int]
                $Row.Decimal | Should -BeOfType [double]
                $Row.Flag | Should -BeOfType [bool]
                $Row.Moment | Should -BeOfType [datetime]
                $Row.Nothing | Should -BeNullOrEmpty
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Plain text' {
        It 'should write a text table for any other extension' {
            $Path = New-TestFilePath -Extension ".txt"
            try {
                Export-QueryResultFile -QueryResult (New-QueryResult -Rows @(
                        [PSCustomObject]@{ Id = 1; Name = "First" }
                        [PSCustomObject]@{ Id = 2; Name = "Second" }
                    )) -Path $Path

                $Content = Get-Content -Path $Path -Raw -Encoding UTF8
                $Content | Should -Match "Id"
                $Content | Should -Match "Name"
                $Content | Should -Match "First"
                $Content | Should -Match "Second"
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }

        It 'should preserve non-ASCII characters in the text output' {
            $Path = New-TestFilePath -Extension ".txt"
            try {
                Export-QueryResultFile -QueryResult (New-QueryResult -Rows @(
                        [PSCustomObject]@{ NonAscii = "Grüße, Ståle — 日本語 — Ω — 🙂" }
                    )) -Path $Path

                $Decoded = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($Path))
                $Decoded | Should -Match "Grüße"
                $Decoded | Should -Match "日本語"
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }

        It 'should trim the leading and trailing blank lines Format-Table adds' {
            $Path = New-TestFilePath -Extension ".txt"
            try {
                Export-QueryResultFile -QueryResult (New-QueryResult -Rows @(
                        [PSCustomObject]@{ Id = 1 }
                    )) -Path $Path

                $Content = Get-Content -Path $Path -Raw -Encoding UTF8
                $Content | Should -Not -Match '^\s*\r?\n'
                $Content.TrimEnd("`r", "`n") | Should -Not -Match '\r?\n\s*$'
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }

        It 'should treat an unknown extension as plain text rather than failing' {
            $Path = New-TestFilePath -Extension ".dat"
            try {
                { Export-QueryResultFile -QueryResult (New-QueryResult -Rows @([PSCustomObject]@{ Id = 1 })) -Path $Path } | Should -Not -Throw
                (Get-Content -Path $Path -Raw -Encoding UTF8) | Should -Match "Id"
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Guard rails' {
        It 'should reject an empty path instead of writing somewhere unexpected' {
            { Export-QueryResultFile -QueryResult (New-QueryResult -Rows @()) -Path "" } | Should -Throw
        }

        It 'should accept a null QueryResult without throwing' {
            $Path = New-TestFilePath -Extension ".json"
            try {
                { Export-QueryResultFile -QueryResult $null -Path $Path } | Should -Not -Throw
            }
            finally {
                Remove-Item -Path $Path -ErrorAction SilentlyContinue
            }
        }
    }
}
