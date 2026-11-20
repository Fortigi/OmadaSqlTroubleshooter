function Confirm-UnsavedQueryOnClose {
    <#
    .SYNOPSIS
        Before the application closes, offers to save every tab's unsaved query, and says whether
        closing may go ahead.

    .DESCRIPTION
        Called first by Invoke-MainFormClosing. Every tab is asked about in tab order, using the same
        rules as closing one tab (Resolve-QuerySavePrompt):

          - a selected query with unsaved changes: offered to be saved;
          - an ad-hoc query with unsaved text: offered to be saved as a new query. Not saving it keeps
            it in the draft cache, and it is offered again at the next start;
          - an empty editor, or nothing changed: not asked about;
          - a disconnected tab: not asked about, because it cannot save. Its ad-hoc query is kept in the
            draft cache all the same.

        Cancel on any prompt stops the close: the tabs asked about before it keep whatever was chosen
        for them, and the window stays open.

        Never stops the close because of its own failure. Should something here throw, the close goes
        ahead and the failure is logged: a window that cannot be closed is worse than the loss it would
        protect against, and an ad-hoc query is in the draft cache regardless.

    .OUTPUTS
        [bool] $true to go on closing, $false when the user cancelled.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $Private:Previous = Get-ActiveTabSession
    try {
        foreach ($Private:Tab in @($Script:Tabs)) {
            $Private:Kind = Resolve-QuerySavePrompt -QueryDoId $Private:Tab.AppConfig.CurrentSqlQuery.DoId -EditorText (Get-TabEditorText -TabSession $Private:Tab) -IsDirty ([bool]$Private:Tab.IsDirty) -Connected (Get-TabConnectionStatus -TabSession $Private:Tab)
            if ($Private:Kind -notin @("SaveExisting", "SaveNew")) {
                continue
            }

            Set-ActiveTabContext -TabSession $Private:Tab
            if ((Request-TabQuerySave -TabSession $Private:Tab -Kind $Private:Kind -ClosingApplication) -eq "Cancel") {
                "Closing the application was cancelled at the save prompt of tab '{0}'." -f $Private:Tab.DisplayName | Write-LogOutput -LogType DEBUG
                return $false
            }
        }
        return $true
    }
    catch {
        "Offering to save unsaved queries failed; closing anyway: {0}" -f $_.Exception.Message | Write-LogOutput -LogType WARNING -SkipDialog
        return $true
    }
    finally {
        if ($null -ne $Private:Previous -and $Script:ActiveTabId -ne $Private:Previous.Id) {
            Set-ActiveTabContext -TabSession $Private:Previous
        }
    }
}
