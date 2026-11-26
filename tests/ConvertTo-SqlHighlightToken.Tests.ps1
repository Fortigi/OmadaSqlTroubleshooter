#Requires -Version 7.0
BeforeAll {
    $Script:Root = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($Script:Root, "src", "Lib", "Functions", "Private", "ConvertTo-SqlHighlightToken.ps1"))
    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)]$Message, $LogType) process { $script:Log += , $Message } }

    $Script:GrammarPath = [System.IO.Path]::Combine($Script:Root, "src", "Monaco", "min", "vs", "basic-languages", "sql", "sql.js")
    $Script:SqlHighlightVocabularyCache = $null
    $Script:Vocabulary = Get-SqlHighlightVocabulary -Path $Script:GrammarPath

    function script:Get-Kinds {
        param([string]$Text)
        @(ConvertTo-SqlHighlightToken -Text $Text -Vocabulary $Script:Vocabulary | Where-Object Kind -ne "Plain" | ForEach-Object { "{0}:{1}" -f $_.Kind, $_.Text })
    }
}

Describe 'Get-SqlHighlightVocabulary' -Tag 'Unit' {
    It 'Should read the editor grammar''s word lists' {
        $Script:Vocabulary.Keywords.Count | Should -BeGreaterThan 300
        $Script:Vocabulary.Operators.Count | Should -BeGreaterThan 20
        $Script:Vocabulary.Functions.Count | Should -BeGreaterThan 200
        $Script:Vocabulary.Keywords.Contains("select") | Should -BeTrue
    }

    It 'Should read the file once' {
        [object]::ReferenceEquals($Script:Vocabulary, (Get-SqlHighlightVocabulary -Path $Script:GrammarPath)) | Should -BeTrue
    }

    It 'Should fall back to the common words, logged, when the grammar cannot be read' {
        $script:Log = @()
        $Fallback = Get-SqlHighlightVocabulary -Path (Join-Path $TestDrive "missing.js")

        $Fallback.Keywords.Contains("SELECT") | Should -BeTrue
        $Fallback.Operators.Contains("AND") | Should -BeTrue
        $Fallback.Functions.Contains("COUNT") | Should -BeTrue
        $script:Log | Should -Match "could not be read"
        $Script:SqlHighlightVocabularyCache = $null
    }
}

Describe 'ConvertTo-SqlHighlightToken' -Tag 'Unit' {
    It 'Should give back exactly the text it was given' {
        $Sql = "SELECT TOP 10 [Select], N'it''s' -- tail`r`nFROM dbo.t /* a`r`nb */ WHERE @@ROWCOUNT > 1.5 AND x = 'open"
        (@(ConvertTo-SqlHighlightToken -Text $Sql -Vocabulary $Script:Vocabulary).Text -join "") | Should -BeExactly $Sql
    }

    It 'Should colour <Case>' -ForEach @(
        @{ Case = 'keywords, in any case'; Sql = "select x from t"; Expected = @("Keyword:select", "Keyword:from") }
        @{ Case = 'operators before keywords'; Sql = "a AND b OR NOT c"; Expected = @("Operator:AND", "Operator:OR", "Operator:NOT") }
        @{ Case = 'a function as the editor does'; Sql = "COUNT(*)"; Expected = @("Function:COUNT") }
        @{ Case = 'strings, N strings and doubled quotes'; Sql = "N'it''s', 'x'"; Expected = @("String:N'it''s'", "String:'x'") }
        @{ Case = 'an unclosed string to the end'; Sql = "WHERE a = 'open FROM"; Expected = @("Keyword:WHERE", "String:'open FROM") }
        @{ Case = 'line comments'; Sql = "1 -- SELECT"; Expected = @("Number:1", "Comment:-- SELECT") }
        @{ Case = 'block comments over lines, and unclosed'; Sql = "/* a`nb */ x /* open"; Expected = @("Comment:/* a`nb */", "Comment:/* open") }
        @{ Case = 'no comment inside a string'; Sql = "'-- no'"; Expected = @("String:'-- no'") }
        @{ Case = 'variables'; Sql = "@id, @@ROWCOUNT"; Expected = @("Variable:@id", "Variable:@@ROWCOUNT") }
        @{ Case = 'numbers, decimal and hexadecimal'; Sql = "1, 2.5, 0x1F"; Expected = @("Number:1", "Number:2.5", "Number:0x1F") }
        @{ Case = 'nothing in a bracketed or quoted name'; Sql = '[FROM], "SELECT"'; Expected = @() }
        @{ Case = 'nothing in an ordinary name'; Sql = "tblDataObject"; Expected = @() }
    ) {
        Get-Kinds -Text $Sql | Should -Be $Expected
    }

    It 'Should give nothing for no text' {
        @(ConvertTo-SqlHighlightToken -Text "" -Vocabulary $Script:Vocabulary).Count | Should -Be 0
        @(ConvertTo-SqlHighlightToken -Text $null -Vocabulary $Script:Vocabulary).Count | Should -Be 0
    }
}
