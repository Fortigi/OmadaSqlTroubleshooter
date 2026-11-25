function Save-TabQueryForClose {
    <#
    .SYNOPSIS
        Saves a tab's query synchronously, because the tab - or the application - is about to close.

    .DESCRIPTION
        The ordinary save (Invoke-SaveEditorValue) first reads the editor through an
        ExecuteScriptAsync round-trip and saves from its completion. Nothing can wait for that while
        the main window is closing, and closing a tab used to queue its teardown behind it. Here the
        text Monaco last reported (Get-TabEditorText) is saved directly with Save-Query, which is
        synchronous, so the caller knows whether it worked before anything is torn down.

        Must be called with the tab already made active (Set-ActiveTabContext): Save-Query works on the
        active tab's state.

    .PARAMETER TabSession
        The tab.

    .PARAMETER Kind
        SaveExisting, or SaveNew for an ad-hoc query (a name is asked for).

    .OUTPUTS
        [string] Saved, Failed, or Cancelled (the user cancelled the name prompt).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession,

        [Parameter(Mandatory = $true)]
        [ValidateSet("SaveExisting", "SaveNew")]
        [string]$Kind
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - TabSession={4} Kind={5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $TabSession.Id, $Kind))

        $Script:RunTimeData.QueryText = Get-TabEditorText -TabSession $TabSession

        if ($Kind -eq "SaveNew") {
            $Private:Name = Request-NewSqlQueryName -TabSession $TabSession -Message ("Save '{0}' in Omada as:" -f (Get-TabName -TabSession $TabSession))
            if ($null -eq $Private:Name) {
                return "Cancelled"
            }
            $Script:RunTimeData.PendingQueryName = $Private:Name
        }

        $Private:Result = Save-Query -NewQuery:($Kind -eq "SaveNew")
        if ($null -eq $Private:Result -or $Private:Result -is [System.Management.Automation.ErrorRecord]) {
            return "Failed"
        }

        $TabSession.IsDirty = $false
        Update-TabHeaderTitle -TabSession $TabSession
        Sync-AdHocQueryDraft -TabSession $TabSession
        return "Saved"
    }
    catch {
        "Saving '{0}' failed: {1}" -f $TabSession.DisplayName, $_.Exception.Message | Write-LogOutput -LogType WARNING -SkipDialog
        return "Failed"
    }
}
