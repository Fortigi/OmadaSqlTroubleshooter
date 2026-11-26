function ConvertTo-SqlHighlightToken {
    <#
    .SYNOPSIS
        Splits SQL into the pieces syntax highlighting colours: keywords, operators, functions,
        variables, strings, comments, numbers and everything else.

    .DESCRIPTION
        For the read-only SQL views (the query details' SQL tab, the history window's old and new
        value), which are RichTextBoxes rather than editors. The words come from the editor's own T-SQL
        grammar (Get-SqlHighlightVocabulary), so a word is coloured the same here as in the editor.

        Scanned left to right, first match wins:

          Comment    /* ... */ (to the end of the text when unclosed) and -- to the end of the line
          String     '...' and N'...', with '' inside; to the end of the text when unclosed
          Plain      [bracketed] and "quoted" identifiers - a keyword in brackets is a name
          Variable   @name, @@name
          Number     123, 1.5, 0x1F
          Operator / a word, by the vocabulary, in the editor's order (operator, then function, then
          Function / keyword); any other word is Plain
          Keyword
          Plain      whitespace, punctuation, anything else

        The pieces put back together are exactly the text: nothing is lost or added.

    .PARAMETER Text
        The SQL.

    .PARAMETER Vocabulary
        The words (Get-SqlHighlightVocabulary).

    .OUTPUTS
        [PSCustomObject[]] @{ Text; Kind }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        $Vocabulary
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return
    }

    $Private:Pattern = '(?<Comment>/\*[\s\S]*?(?:\*/|$)|--[^\r\n]*)|(?<String>N?''(?:[^'']|'''')*(?:''|$))|(?<Identifier>\[[^\]]*\]?|"[^"]*"?)|(?<Variable>@@?[A-Za-z_][\w@$#]*)|(?<Number>\b0x[0-9A-Fa-f]+\b|\b\d+(?:\.\d+)?\b)|(?<Word>[A-Za-z_][\w$#]*)|(?<Other>[\s\S])'
    foreach ($Private:Match in [regex]::Matches($Text, $Private:Pattern)) {
        [PSCustomObject]@{ Text = $Private:Match.Value; Kind = Get-SqlHighlightKind -Match $Private:Match -Vocabulary $Vocabulary }
    }
}

function Get-SqlHighlightKind {
    <#
    .SYNOPSIS
        Which kind of piece a ConvertTo-SqlHighlightToken match is.

    .OUTPUTS
        [string] Comment, String, Variable, Number, Keyword, Operator, Function or Plain.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Text.RegularExpressions.Match]$Match,

        [Parameter(Mandatory = $true)]
        $Vocabulary
    )

    foreach ($Private:Group in @("Comment", "String", "Variable", "Number")) {
        if ($Match.Groups[$Private:Group].Success) {
            return $Private:Group
        }
    }

    if ($Match.Groups["Word"].Success) {
        $Private:Word = $Match.Value.ToUpperInvariant()
        # In the editor grammar's own order (its tokenizer's "cases"): a word on more than one list -
        # COUNT is a keyword and a built-in function - is coloured as the editor colours it.
        if ($Vocabulary.Operators.Contains($Private:Word)) { return "Operator" }
        if ($Vocabulary.Functions.Contains($Private:Word)) { return "Function" }
        if ($Vocabulary.Keywords.Contains($Private:Word)) { return "Keyword" }
    }
    return "Plain"
}

function Get-SqlHighlightVocabulary {
    <#
    .SYNOPSIS
        The T-SQL words syntax highlighting knows, read from the editor's own grammar - Monaco's
        basic-languages/sql/sql.js, which this module ships - once per session.

    .DESCRIPTION
        The editor colours its keywords, operators and built-in functions from the lists in that file
        (keywords, operators, builtinFunctions); reading the same lists keeps the read-only views and
        the editor in agreement, and leaves one list to maintain - Monaco's.

        When the file cannot be read, a short list of the most common words is used instead, so the
        views are still highlighted, if less completely.

    .PARAMETER Path
        The grammar file.

    .OUTPUTS
        [PSCustomObject] @{ Keywords; Operators; Functions } - case-insensitive sets of upper-case words.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "Monaco\min\vs\basic-languages\sql\sql.js")
    )

    if ($null -ne $Script:SqlHighlightVocabularyCache -and $Script:SqlHighlightVocabularyCache.Path -eq $Path) {
        return $Script:SqlHighlightVocabularyCache.Vocabulary
    }

    $Private:Lists = @{ keywords = @(); operators = @(); builtinFunctions = @() }
    try {
        $Private:Grammar = Get-Content -Path $Path -Raw -ErrorAction Stop
        foreach ($Private:Name in @($Private:Lists.Keys)) {
            $Private:Found = [regex]::Match($Private:Grammar, ('{0}:\[(.*?)\]' -f $Private:Name))
            $Private:Lists[$Private:Name] = @([regex]::Matches($Private:Found.Groups[1].Value, '"([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
        }
    }
    catch {
        "The editor's SQL grammar could not be read for highlighting: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }

    if ($Private:Lists.keywords.Count -eq 0) {
        $Private:Lists.keywords = @("SELECT", "FROM", "WHERE", "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "ON", "GROUP", "BY", "ORDER", "HAVING", "TOP", "DISTINCT", "AS", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "WITH", "UNION", "CASE", "WHEN", "THEN", "ELSE", "END", "DECLARE", "BEGIN", "IF", "ASC", "DESC", "NULL", "IS", "CROSS", "APPLY", "OVER", "PARTITION")
        $Private:Lists.operators = @("AND", "OR", "NOT", "IN", "LIKE", "BETWEEN", "EXISTS", "ALL", "ANY", "SOME")
        $Private:Lists.builtinFunctions = @("COUNT", "SUM", "MIN", "MAX", "AVG", "CAST", "CONVERT", "ISNULL", "COALESCE", "GETDATE", "DATEADD", "DATEDIFF", "LEN", "SUBSTRING", "ROW_NUMBER")
    }

    $Private:Vocabulary = [PSCustomObject]@{
        Keywords  = New-SqlWordSet -Word $Private:Lists.keywords
        Operators = New-SqlWordSet -Word $Private:Lists.operators
        Functions = New-SqlWordSet -Word $Private:Lists.builtinFunctions
    }
    $Script:SqlHighlightVocabularyCache = [PSCustomObject]@{ Path = $Path; Vocabulary = $Private:Vocabulary }
    return $Private:Vocabulary
}

function New-SqlWordSet {
    <#
    .SYNOPSIS
        A case-insensitive set of words, upper-cased.

    .OUTPUTS
        [System.Collections.Generic.HashSet[string]]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$Word = @()
    )

    $Private:Set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Private:Item in $Word) {
        $null = $Private:Set.Add($Private:Item.ToUpperInvariant())
    }
    return , $Private:Set
}

function Set-SqlRichText {
    <#
    .SYNOPSIS
        Shows SQL, highlighted, in a read-only RichTextBox: the editor's colours (Monaco's light theme)
        and its font.

    .DESCRIPTION
        One paragraph with a run per piece (ConvertTo-SqlHighlightToken) and a line break per line
        break. The document is made as wide as its longest line so lines do not wrap and the box
        scrolls horizontally, as the editor does.

    .PARAMETER RichTextBox
        The box.

    .PARAMETER Text
        The SQL.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $RichTextBox,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    $Private:Colour = @{
        Keyword  = "#FF0000FF"
        Operator = "#FF778899"
        Function = "#FFFF00FF"
        String   = "#FFFF0000"
        Comment  = "#FF008000"
        Number   = "#FF098658"
        Variable = "#FF001080"
        Plain    = "#FF000000"
    }

    $Private:Paragraph = [System.Windows.Documents.Paragraph]::new()
    $Private:Paragraph.Margin = [System.Windows.Thickness]::new(0)
    foreach ($Private:Token in @(ConvertTo-SqlHighlightToken -Text $Text -Vocabulary (Get-SqlHighlightVocabulary))) {
        Add-SqlRichTextToken -Paragraph $Private:Paragraph -Token $Private:Token -Colour $Private:Colour[$Private:Token.Kind]
    }

    $Private:Document = [System.Windows.Documents.FlowDocument]::new($Private:Paragraph)
    $Private:Document.FontFamily = [System.Windows.Media.FontFamily]::new("Consolas")
    $Private:Document.FontSize = 13
    $Private:Document.PagePadding = [System.Windows.Thickness]::new(4)
    $Private:Longest = @(([string]$Text) -split "\r?\n" | ForEach-Object { $_.Length } | Sort-Object -Descending)[0]
    $Private:Document.PageWidth = [Math]::Max(200, 8 * [int]$Private:Longest + 40)
    $RichTextBox.Document = $Private:Document
}

function Add-SqlRichTextToken {
    <#
    .SYNOPSIS
        Adds one highlighted piece to a paragraph: a run in its colour, with a line break for each of
        its line breaks (a comment or a string can span lines).

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Paragraph,

        [Parameter(Mandatory = $true)]
        $Token,

        [Parameter(Mandatory = $true)]
        [string]$Colour
    )

    $Private:Brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Colour)
    $Private:Lines = $Token.Text -split "\r?\n"
    for ($Private:Index = 0; $Private:Index -lt $Private:Lines.Count; $Private:Index++) {
        if ($Private:Index -gt 0) {
            $Paragraph.Inlines.Add([System.Windows.Documents.LineBreak]::new())
        }
        if ($Private:Lines[$Private:Index].Length -gt 0) {
            $Private:Run = [System.Windows.Documents.Run]::new($Private:Lines[$Private:Index])
            $Private:Run.Foreground = $Private:Brush
            $Paragraph.Inlines.Add($Private:Run)
        }
    }
}
