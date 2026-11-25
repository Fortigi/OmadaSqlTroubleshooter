function Invoke-MainFormClosing {
    <#
    .SYNOPSIS
        The main window's Closing handler: offer to save unsaved queries, then persist the session and
        shut the background workers down.

    .DESCRIPTION
        Moved out of MainForm.Definition so the order is one readable unit:

          1. Confirm-UnsavedQueryOnClose. Cancel keeps the window open (Closing is cancelled) and
             nothing below runs - the state is still "Open", so the application carries on as if the
             close had never been asked for.
          2. Every tab's ad-hoc draft is brought up to date, so what was not saved is on disk before
             the process ends, whatever the timer last wrote.
          3. Tab sessions and window measurements are saved, the other windows are closed.
          4. The background pools are closed last and best-effort: left open their threads keep the
             process alive after the window has gone (issue #40), and a failure there must not cost
             the saved sessions above.

    .PARAMETER ClosingEventArgs
        The CancelEventArgs of the Closing event.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ClosingEventArgs
    )

    if (-not (Confirm-UnsavedQueryOnClose)) {
        $ClosingEventArgs.Cancel = $true
        return
    }

    $Script:MainForm.State = "Closing"

    foreach ($Private:Tab in @($Script:Tabs)) {
        Sync-AdHocQueryDraft -TabSession $Private:Tab
    }

    Save-TabSessions
    Save-FormMeasurements
    if (Test-LogFormIsVisible) {
        $Script:LogForm.Definition.Close()
    }
    if (Test-SqlHistoryFormOpen) {
        $Script:SqlHistoryForm.Definition.Close()
    }
    if (Test-SqlSchemaFormIsVisible) {
        $Script:SqlSchemaForm.Definition.Close()
    }

    Close-OmadaRequestPool
    Close-SqlDiagnosticPool
}
