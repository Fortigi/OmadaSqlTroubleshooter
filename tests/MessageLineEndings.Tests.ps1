#Requires -Version 7.0
# Reported on #83: two messages used "`n`r" - a line feed followed by a carriage return, which is
# backwards. Anything treating CR as "return to column 0" renders the following text over the top of
# the line just written, so the dialog reads as mangled rather than as two lines.
#
# Cheap to get wrong and invisible until someone looks at the dialog, so it is asserted across every
# source file rather than only the two that were reported.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $script:SourceFiles = @(Get-ChildItem -Path (Join-Path $ParentPath -ChildPath "src\Lib") -Filter *.ps1 -Recurse)
}

Describe "Message line endings" {
    It "finds no reversed CRLF pair in any source file" {
        # Tokenized rather than searched as text, for two reasons. A deliberate blank line is written
        # "`r`n`r`n", which CONTAINS the reversed pair as a substring, so a plain search reports every
        # correct one as a defect. And a comment explaining the defect necessarily quotes the wrong
        # form - the fix for this very issue does - which a text search also flags. Only a string
        # literal can render, so only string literals are inspected.
        $Private:Offenders = foreach ($Private:File in $script:SourceFiles) {
            $Private:Tokens = $null
            [System.Management.Automation.Language.Parser]::ParseFile($Private:File.FullName, [ref]$Private:Tokens, [ref]$null) | Out-Null

            foreach ($Private:Token in $Private:Tokens) {
                if ($Private:Token.Kind -notin @("StringExpandable", "StringLiteral")) { continue }

                $Private:Text = $Private:Token.Extent.Text
                foreach ($Private:Match in [regex]::Matches($Private:Text, '`n`r')) {
                    $Private:Before = if ($Private:Match.Index -ge 2) { $Private:Text.Substring($Private:Match.Index - 2, 2) } else { "" }
                    $Private:After = if (($Private:Match.Index + 6) -le $Private:Text.Length) { $Private:Text.Substring($Private:Match.Index + 4, 2) } else { "" }

                    # Part of "`r`n`r`n" - a deliberate blank line - if "`r" precedes and "`n" follows.
                    if ($Private:Before -eq '`r' -and $Private:After -eq '`n') { continue }

                    "{0}: {1}" -f $Private:File.Name, $Private:Token.Extent.StartLineNumber
                }
            }
        }

        @($Private:Offenders) -join "; " | Should -BeNullOrEmpty
    }

    It "still has the two messages that were wrong, now correct" {
        $Private:Source = Get-Content -Path (Join-Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "src\Lib\Functions\Private") "Resolve-OmadaRequestFailure.ps1") -Raw

        $Private:Source | Should -Match 'Error returned by Omada:`r`n`r`n'
        $Private:Source | Should -Match 'Access denied to \{0\}, message:`r`n'
    }
}
