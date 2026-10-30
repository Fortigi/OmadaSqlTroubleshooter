function Invoke-EditorContentChanged {
    <#
    .SYNOPSIS
        Handles the editor's 'contentChanged' message: marks the tab as having unsaved changes and
        schedules the debounced validation.

    .DESCRIPTION
        Monaco posts 'contentChanged' on EVERY edit, so this runs once per keystroke on the WPF
        dispatcher, and anything it does is paid for while the user types (issue #185).

        The tab header is refreshed only when the dirty flag actually flips. The header shows "*" for
        a tab with unsaved changes, and nothing else in it depends on the editor content, so after the
        first keystroke every further refresh rebuilt the same title for nothing.

        Nothing here logs. A line per keystroke says the same thing every time, costs UI-thread time
        even when the level filters it out (Write-LogOutput resolves its context before it applies
        the level), and buries everything else in the log.

    .PARAMETER TabSession
        The tab whose editor changed.

    .OUTPUTS
        None.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $TabSession
    )

    if ($null -eq $TabSession) {
        return
    }

    if (-not $TabSession.IsDirty) {
        $TabSession.IsDirty = $true
        Update-TabHeaderTitle -TabSession $TabSession
    }

    # Push the syntax-validation debounce timer forward. This only restarts a timer - the parse
    # itself happens once the user stops typing, on a worker (Start-SqlDiagnosticBackground).
    Request-SqlSyntaxValidation -TabSession $TabSession
}
