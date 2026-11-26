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
            # Discarded, deliberately. MessageBox.Show returns the button pressed ("OK"), and anything
            # not discarded here becomes output of Write-LogOutput - and so of every function that logs
            # a warning and then returns a value: "Select a query first" followed by "return $null"
            # returned "OK" instead, and the caller went on with no query (a DoId of "").
            $null = Show-WinFormsMessageBox -Owner $Private:DialogOwner -Text (Limit-MessageBoxText -Text $Text) -Title $Title -Icon $Icon
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

function Show-WinFormsMessageBox {
    <#
    .SYNOPSIS
        Shows a WinForms message box with an OK button, owned by -Owner when there is one.

    .OUTPUTS
        [System.Windows.Forms.DialogResult]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Owner,

        [string]$Text,

        [string]$Title,

        $Icon
    )

    if ($null -ne $Owner) {
        return [System.Windows.Forms.MessageBox]::Show($Owner, $Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
    }
    return [System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
}
