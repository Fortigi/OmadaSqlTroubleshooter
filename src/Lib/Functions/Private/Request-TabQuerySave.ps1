function Request-TabQuerySave {
    <#
    .SYNOPSIS
        Asks what to do with a closing tab's unsaved query, and does it.

    .DESCRIPTION
        Shared by closing one tab (Close-TabSession) and closing the application
        (Confirm-UnsavedQueryOnClose), so both ask the same question and act on it the same way.

          SaveExisting / SaveNew  Save, Don't save or Cancel. A save that fails asks whether to close
                                  without saving, so a failed save is never silently a lost one.
          Unavailable             The tab is disconnected and cannot save: Close or Cancel.

        Escape and the window's close button mean Cancel.

        Must be called with the tab already made active (Set-ActiveTabContext).

    .PARAMETER TabSession
        The tab.

    .PARAMETER Kind
        Resolve-QuerySavePrompt's answer.

    .PARAMETER ClosingApplication
        The whole application is closing, which changes what the prompt says about an ad-hoc query.

    .PARAMETER NewQuery
        The editor is about to be cleared for a new query rather than closed; the question and the
        "close anyway" answers say so.

    .OUTPUTS
        [string] Saved, Discarded or Cancel.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession,

        [Parameter(Mandatory = $true)]
        [ValidateSet("SaveExisting", "SaveNew", "Unavailable")]
        [string]$Kind,

        [switch]$ClosingApplication,

        [switch]$NewQuery
    )

    $Private:Message = Get-QuerySavePromptMessage -Kind $Kind -Name (Get-TabName -TabSession $TabSession) -ClosingApplication:$ClosingApplication -NewQuery:$NewQuery
    $Private:Discard = if ($NewQuery) { "Discard" } else { "Close" }

    if ($Kind -eq "Unavailable") {
        $Private:Close = Open-ChoiceForm -Title "Unsaved changes" -Message $Private:Message -LeftButtonText $Private:Discard -RightButtonText "Cancel"
        return $(if ($Private:Close -eq $true) { "Discarded" } else { "Cancel" })
    }

    $Private:Choice = Open-ChoiceForm -Title "Unsaved changes" -Message $Private:Message -LeftButtonText "Save" -RightButtonText "Don't save" -ExtraButtonText "Cancel" -LeftButtonReturnValue "Save" -RightButtonReturnValue "Discard" -ExtraButtonReturnValue "Cancel"
    if ($Private:Choice -eq "Discard") {
        return "Discarded"
    }
    if ($Private:Choice -ne "Save") {
        return "Cancel"
    }

    $Private:Outcome = Save-TabQueryForClose -TabSession $TabSession -Kind $Kind
    if ($Private:Outcome -eq "Saved") {
        return "Saved"
    }
    if ($Private:Outcome -eq "Cancelled") {
        return "Cancel"
    }

    $Private:Anyway = Open-ChoiceForm -Title "Not saved" -Message ("'{0}' could not be saved; see the log for why. {1} it without saving?" -f (Get-TabName -TabSession $TabSession), $Private:Discard) -LeftButtonText ("{0} anyway" -f $Private:Discard) -RightButtonText "Cancel"
    return $(if ($Private:Anyway -eq $true) { "Discarded" } else { "Cancel" })
}
