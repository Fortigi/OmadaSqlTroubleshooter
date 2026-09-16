function Update-LogFormSessionLogPath {
    <#
    .SYNOPSIS
        Puts the log window's session-log-file row in step with what is actually being written.

    .DESCRIPTION
        Where this session's log is being written (issue #121). Shown rather than only offered behind
        the "Folder" button, because the commonest thing a user needs to do with it is put it in a
        support ticket - and because a session that could not open a file has to be able to say so,
        which a button cannot.

        Its own function since issue #138, which made this reachable twice: once when the window
        opens, and again every time the "Write log file" checkbox starts or stops the file. The label
        and the Folder button have to agree with the file after both.

        Both elements are checked, not just the TextBlock. Assigning to a property of $null throws,
        Open-LogForm's catch logs an ERROR, and an ERROR under $ErrorActionPreference = Stop throws
        again - so a XAML mismatch would turn "open the log window" into an error cascade over a
        label.

    .NOTES
        Reads the live state rather than the configuration: a session whose configured folder could
        not be used is writing somewhere else, or nowhere.
    #>

    [CmdLetBinding()]
    param()

    if ($null -eq $Script:LogForm -or $null -eq $Script:LogForm.Elements) {
        return
    }

    if ($null -eq $Script:LogForm.Elements.TextBlockSessionLogPath -or $null -eq $Script:LogForm.Elements.ButtonOpenLogFolder) {
        return
    }

    if ($null -ne $Script:SessionLogFile -and ![string]::IsNullOrWhiteSpace($Script:SessionLogFile.Path)) {
        $Script:LogForm.Elements.TextBlockSessionLogPath.Text = $Script:SessionLogFile.Path
        $Script:LogForm.Elements.TextBlockSessionLogPath.ToolTip = $Script:SessionLogFile.Path
        $Script:LogForm.Elements.ButtonOpenLogFolder.IsEnabled = $true
        return
    }

    $Script:LogForm.Elements.TextBlockSessionLogPath.Text = "No session log file is being written."
    $Script:LogForm.Elements.TextBlockSessionLogPath.ToolTip = "Off by default: tick Write log file to start writing one now. If it is already ticked, the file could not be opened. Export Log File still saves what this window is showing."
    $Script:LogForm.Elements.ButtonOpenLogFolder.IsEnabled = $false
}
