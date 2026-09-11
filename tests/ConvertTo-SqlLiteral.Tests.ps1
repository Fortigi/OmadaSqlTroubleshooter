#Requires -Version 7.0
# Tests for the T-SQL literal formatting of issue #103.
#
# Two things are asserted here that ordinary unit tests would miss:
#
#   * The culture matrix. Every formatting assertion is re-run under nl-NL, en-US and tr-TR and must
#     produce byte-identical output. A fixed format string is not a fixed rendering, and the failures
#     this guards against - "12,50", "20-11-2019" - are silent wrong answers on the server rather
#     than errors.
#   * The round trip. The generated literals are parsed with the real, pinned ScriptDom assembly,
#     which is the same parser the editor's syntax pass uses. Asserting the exact text is not enough
#     for output that is designed to be executed; it also has to parse.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Resolve-StrictBoolean.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-QueryResultValueKind.ps1")
    . (Join-Path $PrivatePath -ChildPath "ConvertTo-SqlLiteral.ps1")

    function Get-ScriptDomAssemblyPath {
        <#
            Resolves a ScriptDom assembly to test against, exactly as Get-SqlSyntaxDiagnostic.Tests
            does: the copy the module has already installed when there is one, otherwise the pinned
            package, downloaded and verified against the pinned SHA-256 before it is used.
        #>
        $Lock = Import-PowerShellDataFile -Path (Join-Path $ParentPath -ChildPath "src\DependencyLock.psd1")
        $Artifact = @($Lock.Artifacts | Where-Object { $_.Id -eq "Microsoft.SqlServer.TransactSql.ScriptDom" })[0]
        if ($null -eq $Artifact) {
            return $null
        }

        $Installed = Join-Path ([System.Environment]::GetFolderPath("LocalApplicationData")) "OmadaSqlTroubleshooter\Bin\Microsoft.SqlServer.TransactSql.ScriptDom.dll"
        if (Test-Path $Installed -PathType Leaf) {
            return $Installed
        }

        $CacheRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("OmadaSqlTroubleshooter.ScriptDom.{0}" -f $Artifact.Version)
        $Cached = Join-Path $CacheRoot "Microsoft.SqlServer.TransactSql.ScriptDom.dll"
        if (Test-Path $Cached -PathType Leaf) {
            return $Cached
        }

        try {
            New-Item -Path $CacheRoot -ItemType Directory -Force | Out-Null
            $Package = Join-Path $CacheRoot "package.zip"
            Invoke-WebRequest -Uri $Artifact.Url -OutFile $Package

            $ActualHash = (Get-FileHash -Path $Package -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($ActualHash -ne $Artifact.Sha256) {
                Remove-Item -Path $Package -Force -ErrorAction SilentlyContinue
                return $null
            }

            $Expanded = Join-Path $CacheRoot "expanded"
            Expand-Archive -Path $Package -DestinationPath $Expanded -Force
            $Source = Get-ChildItem -Path $Expanded -Filter "Microsoft.SqlServer.TransactSql.ScriptDom.dll" -Recurse |
                Where-Object { $_.Directory.Name -eq "net8.0" } |
                Select-Object -First 1
            if ($null -eq $Source) {
                return $null
            }

            Copy-Item -Path $Source.FullName -Destination $Cached -Force
            Remove-Item -Path $Expanded -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $Package -Force -ErrorAction SilentlyContinue
            return $Cached
        }
        catch {
            return $null
        }
    }

    $AssemblyPath = Get-ScriptDomAssemblyPath
    $Script:ScriptDomLoaded = $false
    if (![string]::IsNullOrWhiteSpace($AssemblyPath) -and (Test-Path $AssemblyPath -PathType Leaf)) {
        try {
            Add-Type -Path $AssemblyPath -ErrorAction Stop
            $Script:ScriptDomLoaded = $true
        }
        catch {
            # Already loaded into this session by another test file is a success, not a failure.
            $Script:ScriptDomLoaded = $null -ne ([System.AppDomain]::CurrentDomain.GetAssemblies() |
                    Where-Object { $_.GetName().Name -eq "Microsoft.SqlServer.TransactSql.ScriptDom" })
        }
    }

    function Test-SqlParses {
        <#
            Parses a complete statement built around the supplied literal and returns the parse
            errors. An empty result means the literal is syntactically valid where it was placed.
        #>
        param(
            [string]$Script
        )

        $Parser = New-Object Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser($true)
        $ParseError = New-Object System.Collections.Generic.List[Microsoft.SqlServer.TransactSql.ScriptDom.ParseError]
        $Reader = New-Object System.IO.StringReader($Script)
        try {
            $Parser.Parse($Reader, [ref]$ParseError) | Out-Null
        }
        finally {
            $Reader.Dispose()
        }

        return @($ParseError | ForEach-Object { $_.Message })
    }

    function Invoke-InEveryCulture {
        <#
            Runs a script block once per culture and asserts every run produced the same string.
            tr-TR is in the list for the dotless i, which breaks case-insensitive type name matching;
            nl-NL is there for the decimal comma and the day-first date.
        #>
        param(
            [scriptblock]$Action
        )

        $Original = [System.Threading.Thread]::CurrentThread.CurrentCulture
        $Result = [System.Collections.Generic.List[string]]::new()
        try {
            foreach ($CultureName in @("nl-NL", "en-US", "tr-TR")) {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]::GetCultureInfo($CultureName)
                $Result.Add([string](& $Action))
            }
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $Original
        }

        @($Result | Select-Object -Unique).Count | Should -Be 1 -Because "the output must not depend on the thread culture"
        return $Result[0]
    }
}

Describe "ConvertTo-SqlLiteral" {

    Context "The mapping table from issue #103" {
        It "formats <Name> as <Expected>" -ForEach @(
            @{ Name = "an int"; Value = [int]900; Expected = "900" }
            @{ Name = "a bigint"; Value = [int64]::MaxValue; Expected = "9223372036854775807" }
            @{ Name = "a negative int"; Value = [int]-42; Expected = "-42" }
            @{ Name = "zero"; Value = [int]0; Expected = "0" }
            @{ Name = "a decimal keeping its scale"; Value = 12.50d; Expected = "12.50" }
            @{ Name = "a negative decimal"; Value = -3.25d; Expected = "-3.25" }
            @{ Name = "a zero-scale decimal"; Value = 42d; Expected = "42" }
            @{ Name = "a double"; Value = [double]1.5; Expected = "1.5" }
            @{ Name = "bit true"; Value = $true; Expected = "1" }
            @{ Name = "bit false"; Value = $false; Expected = "0" }
            @{ Name = "NULL"; Value = $null; Expected = "NULL" }
            @{ Name = "an ASCII string"; Value = "IDG-900"; Expected = "'IDG-900'" }
            @{ Name = "a leading-zero code"; Value = "007"; Expected = "'007'" }
            @{ Name = "an all-digit string"; Value = "12345"; Expected = "'12345'" }
            @{ Name = "a non-ASCII string"; Value = "Müller"; Expected = "N'Müller'" }
            @{ Name = "a CJK string"; Value = "日本語"; Expected = "N'日本語'" }
            @{ Name = "the empty string"; Value = ""; Expected = "''" }
            @{ Name = "a datetime"; Value = [datetime]"2019-11-20T13:55:09"; Expected = "'2019-11-20T13:55:09.000'" }
            @{ Name = "a sub-millisecond datetime2"; Value = [datetime]"2019-11-20T13:55:09.1234567"; Expected = "'2019-11-20T13:55:09.1234567'" }
            @{ Name = "a datetimeoffset"; Value = [datetimeoffset]"2019-11-20T13:55:09+01:00"; Expected = "'2019-11-20T13:55:09.0000000+01:00'" }
            @{ Name = "a time"; Value = [timespan]"13:55:09"; Expected = "'13:55:09.0000000'" }
            @{ Name = "a uniqueidentifier"; Value = [guid]"0f6a1b3c-1111-4a2b-9c01-a00000000900"; Expected = "'0f6a1b3c-1111-4a2b-9c01-a00000000900'" }
            @{ Name = "varbinary"; Value = [byte[]]@(10, 27, 44); Expected = "0x0A1B2C" }
            @{ Name = "empty varbinary"; Value = [byte[]]@(); Expected = "0x" }
        ) {
            ConvertTo-SqlLiteral -Value $Value | Should -BeExactly $Expected
        }

        It "formats a DBNull as NULL" {
            ConvertTo-SqlLiteral -Value ([System.DBNull]::Value) | Should -BeExactly "NULL"
        }
    }

    Context "Escaping - the injection boundary" {
        It "escapes <Name>" -ForEach @(
            @{ Name = "an apostrophe"; Value = "O'Brien"; Expected = "'O''Brien'" }
            @{ Name = "a lone quote"; Value = "'"; Expected = "''''" }
            @{ Name = "a doubled quote"; Value = "''"; Expected = "''''''" }
            @{ Name = "a statement terminator and comment"; Value = "x'); DROP TABLE t; --"; Expected = "'x''); DROP TABLE t; --'" }
            @{ Name = "a block comment opener"; Value = "/* x"; Expected = "'/* x'" }
            @{ Name = "a closing bracket"; Value = "a]b"; Expected = "'a]b'" }
            @{ Name = "a tab"; Value = "a`tb"; Expected = "'a`tb'" }
        ) {
            ConvertTo-SqlLiteral -Value $Value | Should -BeExactly $Expected
        }

        It "keeps an embedded CRLF inside the literal" {
            ConvertTo-SqlLiteral -Value "a`r`nb" | Should -BeExactly "'a`r`nb'"
        }
    }

    Context "The N prefix is emitted only when it is earned" {
        It "does not prefix an ASCII value in a varchar column" {
            ConvertTo-SqlLiteral -Value "plain" -SqlType "varchar(50)" | Should -BeExactly "'plain'"
        }

        It "prefixes an n-type column even when the value is ASCII" {
            ConvertTo-SqlLiteral -Value "plain" -SqlType "nvarchar(50)" | Should -BeExactly "N'plain'"
        }

        It "prefixes a non-ASCII value even in a varchar column, because it would otherwise lose characters" {
            ConvertTo-SqlLiteral -Value "Müller" -SqlType "varchar(50)" | Should -BeExactly "N'Müller'"
        }

        It "does not prefix a date, time or GUID literal" {
            ConvertTo-SqlLiteral -Value ([datetime]"2019-11-20T13:55:09") | Should -Not -Match "^N"
            ConvertTo-SqlLiteral -Value ([guid]::Empty) | Should -Not -Match "^N"
        }
    }

    Context "A Boolean kind holding text is never guessed at (review of PR #106)" {
        It "emits 0 for the string 'False' rather than 1" {
            # [bool]'False' is $true in PowerShell, so a plain cast here would emit 1 for a value
            # that says False - the same silent inversion this whole issue is about. This is
            # reachable once Kind is Boolean because the COLUMN is a bit while the value is text,
            # which is what the SqlType seam enables.
            ConvertTo-SqlLiteral -Value "False" -SqlType "bit" | Should -BeExactly "0"
        }

        It "emits 1 for the string 'True'" {
            ConvertTo-SqlLiteral -Value "True" -SqlType "bit" | Should -BeExactly "1"
        }

        It "falls back to a quoted literal for a bit column holding something that is not a boolean" {
            # Quoting is recoverable - the server rejects it. Guessing a bit value is not, because
            # nothing downstream can tell it went wrong.
            ConvertTo-SqlLiteral -Value "maybe" -SqlType "bit" | Should -BeExactly "'maybe'"
        }

        It "still emits 0 and 1 for real booleans" {
            ConvertTo-SqlLiteral -Value $false -SqlType "bit" | Should -BeExactly "0"
            ConvertTo-SqlLiteral -Value $true -SqlType "bit" | Should -BeExactly "1"
        }
    }

    Context "Precision that cannot be trusted is quoted rather than made up" {
        It "quotes a numeric(38,0) that was deserialised into a Double" {
            # The precision is already gone by the time the value reaches here; what this must not do
            # is emit a confident-looking number that is wrong.
            $Value = [double]1.2345678901234568E+37
            ConvertTo-SqlLiteral -Value $Value | Should -BeExactly "'1.2345678901234568E+37'"
        }

        It "quotes NaN and the infinities, which have no numeric literal" {
            ConvertTo-SqlLiteral -Value ([double]::NaN) | Should -Match "^'"
            ConvertTo-SqlLiteral -Value ([double]::PositiveInfinity) | Should -Match "^'"
        }

        It "still emits an ordinary double as a number" {
            ConvertTo-SqlLiteral -Value ([double]12.5) | Should -BeExactly "12.5"
        }
    }

    Context "Culture independence" {
        It "renders <Name> identically under nl-NL, en-US and tr-TR" -ForEach @(
            @{ Name = "a decimal"; Value = 12.50d; Expected = "12.50" }
            @{ Name = "a double"; Value = [double]1234.5; Expected = "1234.5" }
            @{ Name = "a datetime"; Value = [datetime]"2019-11-20T13:55:09"; Expected = "'2019-11-20T13:55:09.000'" }
            @{ Name = "a datetimeoffset"; Value = [datetimeoffset]"2019-11-20T13:55:09+01:00"; Expected = "'2019-11-20T13:55:09.0000000+01:00'" }
            @{ Name = "a time"; Value = [timespan]"13:55:09"; Expected = "'13:55:09.0000000'" }
            @{ Name = "an ISO timestamp arriving as a string"; Value = "2019-11-20T13:55:09"; Expected = "'2019-11-20T13:55:09.000'" }
            @{ Name = "a large integer"; Value = [int64]1234567890; Expected = "1234567890" }
            @{ Name = "a bit"; Value = $true; Expected = "1" }
        ) {
            $Actual = Invoke-InEveryCulture -Action { ConvertTo-SqlLiteral -Value $Value }
            $Actual | Should -BeExactly $Expected
        }
    }

    Context "Round trip through the real T-SQL parser" {
        BeforeEach {
            # Set-ItResult at run time rather than -Skip: on the It, because -Skip: is evaluated
            # during discovery - before BeforeAll has had a chance to load the assembly - so it
            # would skip every one of these even on a machine where ScriptDom is installed. This is
            # the pattern Get-SqlSyntaxDiagnostic.Tests.ps1 already uses.
            if (-not $Script:ScriptDomLoaded) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
            }
        }

        It "produces a literal that ScriptDom parses for <Name>" -ForEach @(
            @{ Name = "an int"; Value = [int]900 }
            @{ Name = "a decimal"; Value = 12.50d }
            @{ Name = "a bit"; Value = $true }
            @{ Name = "NULL"; Value = $null }
            @{ Name = "a leading-zero code"; Value = "007" }
            @{ Name = "an apostrophe"; Value = "O'Brien" }
            @{ Name = "an injection attempt"; Value = "x'); DROP TABLE t; --" }
            @{ Name = "a block comment opener"; Value = "/* x" }
            @{ Name = "a closing bracket"; Value = "a]b" }
            @{ Name = "an embedded CRLF"; Value = "a`r`nb" }
            @{ Name = "a tab"; Value = "a`tb" }
            @{ Name = "a non-ASCII value"; Value = "Müller" }
            @{ Name = "a datetime"; Value = [datetime]"2019-11-20T13:55:09" }
            @{ Name = "a GUID"; Value = [guid]"0f6a1b3c-1111-4a2b-9c01-a00000000900" }
            @{ Name = "varbinary"; Value = [byte[]]@(10, 27, 44) }
            @{ Name = "Int64.MaxValue"; Value = [int64]::MaxValue }
        ) {
            $Literal = ConvertTo-SqlLiteral -Value $Value
            Test-SqlParses -Script ("SELECT * FROM t WHERE c IN ({0});" -f $Literal) | Should -BeNullOrEmpty
        }

        It "produces an injection literal that parses as exactly one statement, not two" {
            # The escaping assertion above proves the text; this proves the consequence. If the
            # quote doubling ever regressed, this script would parse as a SELECT followed by a DROP.
            $Literal = ConvertTo-SqlLiteral -Value "x'); DROP TABLE t; --"
            $Script = "SELECT * FROM t WHERE c IN ({0});" -f $Literal

            $Parser = New-Object Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser($true)
            $ParseError = New-Object System.Collections.Generic.List[Microsoft.SqlServer.TransactSql.ScriptDom.ParseError]
            $Reader = New-Object System.IO.StringReader($Script)
            try {
                $Fragment = $Parser.Parse($Reader, [ref]$ParseError)
            }
            finally {
                $Reader.Dispose()
            }

            @($ParseError).Count | Should -Be 0
            $Fragment.Batches[0].Statements.Count | Should -Be 1
        }
    }
}
