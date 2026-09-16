function ConvertTo-JavaScriptLiteral {
    <#
    .SYNOPSIS
        Converts one string into one JavaScript string literal, quotes included.

    .DESCRIPTION
        Every payload pushed at the Monaco editor is JavaScript SOURCE handed to
        CoreWebView2.ExecuteScriptAsync, so any text interpolated into it is code unless it is
        escaped as a literal first. Four call sites used to hand-roll that escaping with a
        -replace chain, and three of them never escaped the backslash - which is the whole bug:
        a backslash immediately before a quote consumes the escape, the literal ends early, and
        the remainder of the text runs as script.

        Serialisation replaces the hand-rolled chain because getting this right by hand means
        ordering the replacements correctly (backslash first, always) and remembering every
        character that can terminate a literal. ConvertTo-Json already does both, and it is
        already the established pattern for editor payloads in this module: Get-SqlSchema builds
        its setSchema(...) argument this way, and ConvertTo-EditorDiagnosticScript does the same
        for setDiagnostics(...).

        The returned value INCLUDES its surrounding double quotes, exactly as
        Format-SqlStringLiteral returns its own. Call sites interpolate it bare -
        "window.setEditorValue({0});" - and must NOT wrap it in quotes of their own.

        Two properties of the output that were measured rather than assumed, because the payload
        is JavaScript source and not a JSON document:

          * U+2028 and U+2029 come back as \u2028 and \u2029. They are legal raw inside a JSON
            string but terminate a JavaScript string literal, so a serialiser that passed them
            through would reintroduce this very bug in a subtler form. PowerShell's encoder
            escapes them.
          * "</script>" is NOT escaped, and does not need to be here. This text never enters an
            HTML <script> element - it is handed to ExecuteScriptAsync as source - so there is no
            HTML context to break out of. Any future caller that embeds the result in markup must
            escape it for HTML itself; this function does not promise that.

        Non-ASCII characters are emitted raw. The script travels to WebView2 as a UTF-16 .NET
        string, so they need no escape, and escaping them would only make the payload harder to
        read in a trace.

    .PARAMETER Value
        The text to render as a literal. $null and the empty string both produce "".

    .OUTPUTS
        [string] one JavaScript string literal, including its surrounding quotes.

    .EXAMPLE
        ConvertTo-JavaScriptLiteral -Value "SELECT 1"
        "SELECT 1"

    .EXAMPLE
        ConvertTo-JavaScriptLiteral -Value "C:\temp\file.sql"
        "C:\\temp\\file.sql"

    .NOTES
        No tracer preamble: this is a pure function on the per-push path, and the payload it
        builds is deliberately never traced by content (see Push-ToEditor, issue #111).
    #>

    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    # A [string]-typed parameter already turns $null into "", but the coercion is stated rather
    # than relied upon: an empty literal is the correct rendering of "no text", and the one thing
    # this function must never return is nothing at all - that would leave the call site emitting
    # "window.setEditorValue();" and silently changing the call's arity.
    if ($null -eq $Value) {
        $Value = ""
    }

    # -InputObject, not the pipeline: piping an empty string sends an item, but the parameter form
    # is unambiguous for a value that may legitimately be empty, and it cannot be short-circuited
    # by an upstream $null collapsing the pipeline to zero items.
    return (ConvertTo-Json -InputObject $Value -Compress)
}
