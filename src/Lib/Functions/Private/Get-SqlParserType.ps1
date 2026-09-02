function Get-SqlParserType {
    <#
    .SYNOPSIS
        Resolves the ScriptDom TSqlNNNParser type to parse with, or $null when ScriptDom is not
        loaded.

    .DESCRIPTION
        The parser version is discovered by reflection rather than hard-coded. A literal
        [Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser] in the source would bind the module
        to one T-SQL grammar for ever: bump the pinned package and the newer grammar is downloaded
        but never used, and a syntax the tenant accepts would still be flagged. Enumerating the
        assembly means the newest grammar the pinned package ships is picked up automatically.

        Choosing the NEWEST parser is deliberate. The parsers are cumulative - each version adds
        syntax rather than removing it - so the newest one is the most permissive, and a permissive
        parser is what a false-positive-averse feature wants. It can still disagree with the tenant's
        actual compatibility level, which is exactly why nothing here ever blocks execution and why
        SqlParserVersion is configurable.

    .PARAMETER ParserVersion
        An explicit parser to use, either as the full type name ("TSql160Parser") or as the bare
        version number ("160"). Omit to take the newest parser in the loaded assembly.

    .OUTPUTS
        [Type] the resolved parser type, or $null when ScriptDom is unavailable or the requested
        version does not exist in it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ParserVersion
    )

    # No tracer preamble and no Write-LogOutput: this is called on every keystroke-debounced parse,
    # and it is on the path the privacy rule in issue #61 section 5 covers. It carries no query text, but
    # keeping it silent keeps the whole validation path silent by construction.

    $ParserAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq "Microsoft.SqlServer.TransactSql.ScriptDom" } |
        Select-Object -First 1

    if ($null -eq $ParserAssembly) {
        return $null
    }

    try {
        $ParserType = @($ParserAssembly.GetExportedTypes() | Where-Object { $_.Name -match '^TSql\d+Parser$' })
    }
    catch {
        return $null
    }

    if ($ParserType.Count -eq 0) {
        return $null
    }

    if (![string]::IsNullOrWhiteSpace($ParserVersion)) {
        $RequestedName = $ParserVersion.Trim()
        if ($RequestedName -match '^\d+$') {
            $RequestedName = "TSql{0}Parser" -f $RequestedName
        }
        return ($ParserType | Where-Object { $_.Name -eq $RequestedName } | Select-Object -First 1)
    }

    # Sorted numerically, not lexically: "TSql90Parser" sorts after "TSql180Parser" as a string.
    return ($ParserType |
            Sort-Object -Property @{ Expression = { [int]($_.Name -replace '^TSql(\d+)Parser$', '$1') } } -Descending |
            Select-Object -First 1)
}
