#Requires -Version 7.0
# Tests for GHSA-c36v-qf59-xvm2: JavaScript injection via unescaped payloads pushed at the
# Monaco editor. The payload is JavaScript SOURCE handed to CoreWebView2.ExecuteScriptAsync, not a
# JSON document, so serialisation alone is not proof of safety - two properties below (U+2028 /
# U+2029, and the deliberately unescaped "</script>") are asserted because they were measured
# against that fact rather than assumed from ConvertTo-Json's JSON contract.

$ParentPath = Split-Path -Path $PSScriptRoot -Parent
$PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

# Computed at discovery time (top-level script scope, not inside BeforeAll) because the
# -ForEach data below is evaluated during discovery, before any BeforeAll block runs.
$Script:MigratedCallSites = @(
    (Join-Path $PrivatePath -ChildPath "Set-EditorValue.ps1")
    (Join-Path $ParentPath -ChildPath "src\Lib\Events\SqlHistoryForm.Elements.ButtonRestoreQuery.ps1")
    (Join-Path $PrivatePath -ChildPath "Invoke-OnTreeViewItemShiftClick.ps1")
    (Join-Path $PrivatePath -ChildPath "Initialize-WebViewForTab.ps1")
)

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-JavaScriptLiteral.ps1")
}

Describe "ConvertTo-JavaScriptLiteral" -Tag "Unit" {

    Context "The advisory payload (GHSA-c36v-qf59-xvm2)" {
        It "neutralises a trailing backslash before the closing quote so the literal cannot terminate early" {
            $Payload = "SELECT 1 -- a\'); alert(1); //"
            $Literal = ConvertTo-JavaScriptLiteral -Value $Payload

            # The backslash must be doubled, otherwise it escapes the quote that follows it in the
            # rendered JavaScript source, closing the literal early.
            $Literal | Should -Match ([regex]::Escape('a\\'))

            # The round trip is the strongest proof: the literal, read back as JSON, must be the
            # exact original text - including the single backslash and the apostrophe.
            (ConvertFrom-Json -InputObject $Literal) | Should -BeExactly $Payload
        }
    }

    Context "Escaping - the injection boundary" {
        It "escapes a lone backslash" {
            $Literal = ConvertTo-JavaScriptLiteral -Value "a\b"
            $Literal | Should -BeExactly '"a\\b"'
            (ConvertFrom-Json -InputObject $Literal) | Should -BeExactly "a\b"
        }

        It "escapes a backslash immediately before a quote" {
            $Literal = ConvertTo-JavaScriptLiteral -Value 'a\"b'
            (ConvertFrom-Json -InputObject $Literal) | Should -BeExactly 'a\"b'
        }

        It "escapes a double quote" {
            $Literal = ConvertTo-JavaScriptLiteral -Value 'a"b'
            $Literal | Should -BeExactly '"a\"b"'
            (ConvertFrom-Json -InputObject $Literal) | Should -BeExactly 'a"b'
        }

        It "escapes carriage return, line feed and tab" -ForEach @(
            @{ Name = "CR"; Value = "a`rb" }
            @{ Name = "LF"; Value = "a`nb" }
            @{ Name = "TAB"; Value = "a`tb" }
        ) {
            $Literal = ConvertTo-JavaScriptLiteral -Value $Value
            $Literal | Should -Not -Match "[`r`n`t]"
            (ConvertFrom-Json -InputObject $Literal) | Should -BeExactly $Value
        }

        It "escapes U+2028 and U+2029 to \u2028 and \u2029, which are legal raw JSON but terminate a JavaScript literal" {
            $LineSeparator = [char]0x2028
            $ParagraphSeparator = [char]0x2029

            $LineLiteral = ConvertTo-JavaScriptLiteral -Value "a$($LineSeparator)b"
            $LineLiteral | Should -Match '\\u2028'
            $LineLiteral | Should -Not -Match $LineSeparator

            $ParagraphLiteral = ConvertTo-JavaScriptLiteral -Value "a$($ParagraphSeparator)b"
            $ParagraphLiteral | Should -Match '\\u2029'
            $ParagraphLiteral | Should -Not -Match $ParagraphSeparator

            (ConvertFrom-Json -InputObject $LineLiteral) | Should -BeExactly "a$($LineSeparator)b"
            (ConvertFrom-Json -InputObject $ParagraphLiteral) | Should -BeExactly "a$($ParagraphSeparator)b"
        }
    }

    Context "Null and empty input" {
        It "renders the empty string as the two-character literal" {
            ConvertTo-JavaScriptLiteral -Value "" | Should -BeExactly '""'
        }

        It "renders `$null as the two-character literal" {
            ConvertTo-JavaScriptLiteral -Value $null | Should -BeExactly '""'
        }
    }

    Context "Text that must pass through unchanged" {
        It "emits non-ASCII characters raw" {
            $Value = "Müller 日本語"
            $Literal = ConvertTo-JavaScriptLiteral -Value $Value
            $Literal | Should -Match ([regex]::Escape($Value))
            (ConvertFrom-Json -InputObject $Literal) | Should -BeExactly $Value
        }

        It "does not escape a closing script tag - documented, safe behaviour" {
            # This text never enters an HTML <script> element. It is handed to
            # CoreWebView2.ExecuteScriptAsync as JavaScript source, not embedded in markup, so
            # there is no HTML context for it to break out of. A future caller that puts this
            # result into markup instead must escape it for HTML itself - this function makes no
            # such guarantee.
            $Value = "</script><script>alert(1)</script>"
            $Literal = ConvertTo-JavaScriptLiteral -Value $Value
            $Literal.Contains($Value) | Should -BeTrue
            (ConvertFrom-Json -InputObject $Literal) | Should -BeExactly $Value
        }
    }

    Context "Shape of the output" {
        It "always starts and ends with a double quote" -ForEach @(
            @{ Name = "plain text"; Value = "SELECT 1" }
            @{ Name = "the empty string"; Value = "" }
            @{ Name = "null"; Value = $null }
            @{ Name = "a backslash"; Value = "\" }
        ) {
            $Literal = ConvertTo-JavaScriptLiteral -Value $Value
            $Literal.Substring(0, 1) | Should -BeExactly '"'
            $Literal.Substring($Literal.Length - 1, 1) | Should -BeExactly '"'
        }
    }

    Context "Round trip through ConvertFrom-Json" {
        It "returns the exact original value for <Name>" -ForEach @(
            @{ Name = "an ordinary query"; Value = "SELECT * FROM t WHERE c = 1" }
            @{ Name = "a Windows path"; Value = "C:\temp\file.sql" }
            @{ Name = "an apostrophe"; Value = "O'Brien" }
            @{ Name = "a mixed injection attempt"; Value = "SELECT 1 -- a\'); alert(1); //" }
            @{ Name = "CRLF"; Value = "line1`r`nline2" }
        ) {
            $Literal = ConvertTo-JavaScriptLiteral -Value $Value
            (ConvertFrom-Json -InputObject $Literal) | Should -BeExactly $Value
        }
    }

    Context "The four migrated call sites no longer hand-roll quote escaping" {
        It "does not contain the old backslash-blind quote escape chain in <Path>" -ForEach @(
            $Script:MigratedCallSites | ForEach-Object { @{ Path = $_ } }
        ) {
            $Content = Get-Content -Path $Path -Raw
            $Content | Should -Not -Match ([regex]::Escape('-replace "''", "\''"'))
        }

        It "actually calls ConvertTo-JavaScriptLiteral in <Path>" -ForEach @(
            $Script:MigratedCallSites | ForEach-Object { @{ Path = $_ } }
        ) {
            # A missing old-style escape chain is not proof of a correct migration - it also
            # passes for a file rewritten some other way, or one that stopped pushing to the
            # editor entirely. The positive half of the property is that the new helper is the
            # one doing the escaping.
            $Content = Get-Content -Path $Path -Raw
            $Content | Should -Match ([regex]::Escape('ConvertTo-JavaScriptLiteral'))
        }

        It "does not re-wrap the literal in its own quotes in <Path>" -ForEach @(
            $Script:MigratedCallSites | ForEach-Object { @{ Path = $_ } }
        ) {
            # ConvertTo-JavaScriptLiteral's return value already carries its own surrounding
            # double quotes. "setEditorValue('" - an opening single quote immediately after the
            # call - is the shape of the old hand-quoted call site; its presence here would mean
            # the literal got double-quoted, which breaks the payload rather than escaping it.
            $Content = Get-Content -Path $Path -Raw
            $Content | Should -Not -Match ([regex]::Escape("setEditorValue('"))
        }
    }
}
