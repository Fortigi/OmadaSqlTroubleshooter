function Close-TabSession {
    <#
    .SYNOPSIS
    Closes a tab. Offers to save first when the tab has unsaved query changes or an unsaved ad-hoc
    query (Save / Don't save / Cancel); an empty editor is not offered. Closing the last remaining tab
    leaves only the "+" add tab - no tab is auto-opened.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TabId
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        $TabToClose = $Script:Tabs | Where-Object { $_.Id -eq $TabId } | Select-Object -First 1
        if ($null -eq $TabToClose) {
            "Close-TabSession: tab '{0}' not found." -f $TabId | Write-LogOutput -LogType WARNING
            return
        }

        # Capture whichever tab is actually active before repointing context onto the tab being
        # closed - closing a background tab (e.g. via its own header's close button) must not
        # silently switch the user away from whatever tab they're actually looking at.
        $PreviouslyActiveTab = Get-ActiveTabSession
        $WasActiveTab = ($null -ne $PreviouslyActiveTab -and $PreviouslyActiveTab.Id -eq $TabId)

        # Operate against the tab being closed, so IsDirty/Save act on its own state
        # regardless of which tab happens to be active right now.
        Set-ActiveTabContext -TabSession $TabToClose

        # Everything that actually tears the tab down - disposing WebView2, removing it from the
        # TabControl/$Script:Tabs, and deciding which tab becomes active next - lives in the named
        # function Complete-TabClose.
        #
        # Whether to ask first is Resolve-QuerySavePrompt's decision, shared with closing the whole
        # application: unsaved changes to a selected query, or an unsaved ad-hoc query, are offered to
        # be saved; an empty editor is not. The save is synchronous (Save-TabQueryForClose saves the
        # text Monaco last reported), so the tab is only torn down once the save has succeeded - this
        # used to queue the teardown behind an asynchronous editor read instead.
        $Kind = Resolve-QuerySavePrompt -QueryDoId $TabToClose.AppConfig.CurrentSqlQuery.DoId -EditorText (Get-TabEditorText -TabSession $TabToClose) -IsDirty ([bool]$TabToClose.IsDirty) -Connected ([bool]$Script:ConnectionStatus)
        if ($Kind -ne "None" -and (Request-TabQuerySave -TabSession $TabToClose -Kind $Kind) -eq "Cancel") {
            "Closing tab '{0}' was cancelled." -f $TabToClose.DisplayName | Write-LogOutput -LogType DEBUG
            if ($null -ne $PreviouslyActiveTab) {
                Set-ActiveTabContext -TabSession $PreviouslyActiveTab
            }
            return
        }

        # The tab is going away, and with it any ad-hoc draft it had: closing it was the user's answer.
        Remove-AdHocQueryDraft -TabId $TabToClose.Id

        Complete-TabClose -TabToClose $TabToClose -WasActiveTab $WasActiveTab -PreviouslyActiveTab $PreviouslyActiveTab
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
