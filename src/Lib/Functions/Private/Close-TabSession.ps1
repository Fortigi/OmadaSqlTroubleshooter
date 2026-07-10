function Close-TabSession {
    <#
    .SYNOPSIS
    Closes a tab. Prompts to save first if the tab has unsaved query changes. Never leaves the
    application with zero tabs - closing the last remaining tab immediately opens a fresh one.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TabId
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

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
        # function Complete-TabClose so it can run either immediately (no unsaved changes /
        # Discard) or deferred until an in-flight save completes (see below), without a closure.

        if ($TabToClose.IsDirty) {
            $Choice = Open-ChoiceForm -Title "Unsaved changes" -Message ("Save changes to '{0}' before closing?" -f $TabToClose.DisplayName) -LeftButtonText "Save" -RightButtonText "Discard" -LeftButtonReturnValue 1 -RightButtonReturnValue 2
            if ($Choice -eq 1) {
                # Invoke-SaveEditorValue is asynchronous (it queues a WebView2 script and returns
                # immediately) - disposing/removing the tab right after calling it would race the
                # save and can lose the user's changes. Defer the teardown until that same save
                # Task completes by enqueuing onto the same $Script:PendingWebViewCompletions
                # queue Invoke-SaveEditorValue's own completion uses - entries are processed in
                # the order they were added, so Complete-TabClose only runs after the save itself
                # has finished. TabSession is left $null here since Complete-TabClose already
                # decides the correct active tab itself; the top-level poll timer must not also
                # try to. The teardown state travels on the completion item and is read back out
                # by a plain (non-closure) block so it can resolve this module's private functions.
                Invoke-SaveEditorValue
                $SaveTask = $TabToClose.PendingTask
                if ($null -ne $SaveTask) {
                    $Script:PendingWebViewCompletions.Add([PSCustomObject]@{
                            Task                   = $SaveTask
                            TabSession             = $null
                            TabToClose             = $TabToClose
                            WasActiveTab           = $WasActiveTab
                            PreviouslyActiveTab    = $PreviouslyActiveTab
                            OnCompletedScriptBlock = {
                                param($Completion)
                                Complete-TabClose -TabToClose $Completion.TabToClose -WasActiveTab $Completion.WasActiveTab -PreviouslyActiveTab $Completion.PreviouslyActiveTab
                            }
                        })
                    return
                }
            }
        }

        Complete-TabClose -TabToClose $TabToClose -WasActiveTab $WasActiveTab -PreviouslyActiveTab $PreviouslyActiveTab
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
