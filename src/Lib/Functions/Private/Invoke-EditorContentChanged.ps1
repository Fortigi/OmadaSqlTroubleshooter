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

        The text arrives with the message (Monaco's postEditorText) and is recorded with
        Set-TabEditorText as a user edit, which is also what queues the ad-hoc draft cache to be
        written: the file itself is written later, from the completion poll timer, so typing never
        waits on the disk.

    .PARAMETER TabSession
        The tab whose editor changed.

    .PARAMETER Text
        The editor's text after the change. Omitted by a sender that does not report it, in which
        case nothing is recorded.

    .OUTPUTS
        None.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $TabSession,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    if ($null -eq $TabSession) {
        return
    }

    if ($PSBoundParameters.ContainsKey("Text")) {
        Set-TabEditorText -TabSession $TabSession -Text $Text -UserEdit
    }

    if (-not $TabSession.IsDirty) {
        $TabSession.IsDirty = $true
        Update-TabHeaderTitle -TabSession $TabSession
    }

    # Push the syntax-validation debounce timer forward. This only restarts a timer - the parse
    # itself happens once the user stops typing, on a worker (Start-SqlDiagnosticBackground).
    Request-SqlSyntaxValidation -TabSession $TabSession
}
