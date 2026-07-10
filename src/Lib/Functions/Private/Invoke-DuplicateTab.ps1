function Invoke-DuplicateTab {
    <#
    .SYNOPSIS
    Duplicates a tab: copies its connection state (tenant, authentication, credentials, save
    password, data connection) and its editor SQL into a NEW tab, deliberately NOT copying the
    query name / selected query - the goal is to start a new query from the source tab's content.

    .DESCRIPTION
    Reads the source tab's live editor text asynchronously (editor.getValue()), then hands off to
    Complete-DuplicateTab. The read is enqueued on the shared WebView completion timer with a $null
    TabSession so the timer does not save/restore the active tab around it - Complete-DuplicateTab
    creates the new tab, which becomes active, and that must stick.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TabId
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        $Source = $Script:Tabs | Where-Object { $_.Id -eq $TabId } | Select-Object -First 1
        if ($null -eq $Source) {
            "Invoke-DuplicateTab: source tab '{0}' not found." -f $TabId | Write-LogOutput -LogType WARNING
            return
        }

        $SourceConnected = if ($Source.Id -eq $Script:ActiveTabId) { [bool]$Script:ConnectionStatus } else { [bool]$Source.ConnectionStatus }

        $SourceWeb = $Source.WebView.Object
        if ($null -ne $SourceWeb -and $SourceWeb.IsLoaded -and $null -ne $SourceWeb.CoreWebView2) {
            $Task = $SourceWeb.CoreWebView2.ExecuteScriptAsync("editor.getValue();")
            $Script:PendingWebViewCompletions.Add([PSCustomObject]@{
                    Task                   = $Task
                    TabSession             = $null
                    DuplicateSourceId      = $TabId
                    DuplicateConnected     = $SourceConnected
                    DuplicateTask          = $Task
                    OnCompletedScriptBlock = {
                        param($Completion)
                        $EditorText = ""
                        try {
                            if ($null -ne $Completion.DuplicateTask -and $Completion.DuplicateTask.Status -eq "RanToCompletion") {
                                $Raw = $Completion.DuplicateTask.Result
                                if (![string]::IsNullOrEmpty($Raw)) {
                                    # ExecuteScriptAsync returns the result JSON-encoded; editor.getValue() is a string.
                                    try { $EditorText = $Raw | ConvertFrom-Json } catch { $EditorText = $Raw }
                                }
                            }
                        }
                        catch {
                            $_.Exception.Message | Write-LogOutput -LogType WARNING
                        }
                        Complete-DuplicateTab -SourceTabId $Completion.DuplicateSourceId -SourceConnected ([bool]$Completion.DuplicateConnected) -EditorText $EditorText
                    }
                })
        }
        else {
            # No editor available to read; still duplicate the connection state with an empty editor.
            Complete-DuplicateTab -SourceTabId $TabId -SourceConnected $SourceConnected -EditorText ""
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
