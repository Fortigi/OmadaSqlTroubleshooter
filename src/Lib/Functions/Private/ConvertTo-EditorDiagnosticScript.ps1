function ConvertTo-EditorDiagnosticScript {
    <#
    .SYNOPSIS
        Builds the setDiagnostics(...) call that pushes a set of diagnostics into the Monaco editor.

    .DESCRIPTION
        The single diagnostics channel described in issue #61 section 3. There is deliberately ONE
        seam rather than one per validation pass: the schema pass added later emits the same marker
        shape with Severity "Warning" and its own Source, and needs no change here or in
        src\Monaco\index.html.

        The marker shape is fixed by that contract:

            line, column, endLine, endColumn   one-based, exactly as Monaco's IMarkerData wants them
            severity                           "Error" or "Warning", mapped to monaco.MarkerSeverity
                                               on the JavaScript side so the wire format stays
                                               readable and version-independent
            source                             shown in the editor's hover, and what makes a syntax
                                               error visually distinct from a schema warning

        Kept separate from Get-SqlSyntaxDiagnostic so the payload shape is testable without a parser,
        a WebView2 or a running editor.

    .PARAMETER Diagnostic
        The diagnostics to push. An empty or null collection produces a call that clears the editor's
        markers, which is exactly what a script that has become valid again needs.

    .OUTPUTS
        [string] the JavaScript to hand to Invoke-ExecuteScriptAsync.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        $Diagnostic
    )

    # No tracer preamble: the diagnostics carry identifiers taken from the user's query (issue #61 section 5).

    begin {
        $Collected = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        foreach ($Item in @($Diagnostic)) {
            if ($null -eq $Item) {
                continue
            }
            $Collected.Add([PSCustomObject][Ordered]@{
                    line      = [int]$Item.Line
                    column    = [int]$Item.Column
                    endLine   = [int]$Item.EndLine
                    endColumn = [int]$Item.EndColumn
                    severity  = [string]$Item.Severity
                    message   = [string]$Item.Message
                    source    = [string]$Item.Source
                })
        }
    }

    end {
        # The empty case is written out rather than serialised. Nothing reaches ConvertTo-Json
        # through an empty pipeline, so it returns $null and the call would become
        # "setDiagnostics();" - which throws in the editor instead of clearing the markers.
        if ($Collected.Count -eq 0) {
            return "setDiagnostics([]);"
        }

        # Piped in, NOT passed as -InputObject. -AsArray is what guarantees a JSON array for a
        # single diagnostic - setDiagnostics takes a list, and a lone object would be read as a
        # malformed one - but -InputObject hands the whole collection over as one value, so
        # -InputObject together with -AsArray wraps the array in another array: "[[{...}]]".
        # Through the pipeline each diagnostic arrives on its own and the result is a flat array
        # for none, one and many alike.
        $Json = $Collected | ConvertTo-Json -Depth 3 -Compress -AsArray

        return "setDiagnostics({0});" -f $Json
    }
}
