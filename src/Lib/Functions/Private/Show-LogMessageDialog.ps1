function Show-LogMessageDialog {
    <#
    .SYNOPSIS
    Show a warning or error dialog, owned by the main window.

    .DESCRIPTION
    Extracted from Write-LogOutput so that a message shown immediately and a message held for a tab
    that was off screen go through exactly one implementation. They previously could not have drifted
    apart, because only one of them existed; now that there are two callers, one function is what
    stops them drifting.

    Owned by the main window: without an owner a WinForms message box raised from a WPF application
    is a top-level window with no relationship to it, so Windows is free to order it behind the main
    form - which it did, and because the dialog is modal the application underneath looked hung.

    .PARAMETER Text
    The message body.

    .PARAMETER Title
    The dialog title.

    .PARAMETER Icon
    The MessageBoxIcon to show.
    #>
    [CmdLetBinding()]
    param(
        [string]$Text,
        [string]$Title,
        $Icon
    )

    # A blocking dialog pumps this thread's messages while it is up, which can let the completion
    # poll timer's Tick fire reentrantly nested inside it - suspend it for the duration so that
    # cannot happen (see Suspend-WebViewCompletionPolling.ps1 for why).
    Suspend-WebViewCompletionPolling
    try {
        $Private:DialogOwner = Get-MainFormMessageBoxOwner
        try {
            if ($null -ne $Private:DialogOwner) {
                [System.Windows.Forms.MessageBox]::Show($Private:DialogOwner, (Limit-MessageBoxText -Text $Text), $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
            }
            else {
                [System.Windows.Forms.MessageBox]::Show((Limit-MessageBoxText -Text $Text), $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
            }
        }
        finally {
            if ($null -ne $Private:DialogOwner) {
                try { $Private:DialogOwner.ReleaseHandle() } catch { }
            }
        }

        Restore-MainFormFocus
    }
    finally {
        Resume-WebViewCompletionPolling
    }
}
