function Complete-DuplicateTab {
    <#
    .SYNOPSIS
    Creates the duplicate tab from a source tab's connection state and editor SQL (see
    Invoke-DuplicateTab). The query name / selected query are intentionally left blank so the copy
    is a fresh unsaved query. The editor text is stashed on the new tab as PendingEditorText and
    pushed into Monaco by the tab's NavigationCompleted handler once the editor has loaded.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceTabId,
        [bool]$SourceConnected,
        [string]$EditorText,
        # When set (duplicate *including* the query), the copy is named after the source query with
        # the next free number (Get-IncrementedQueryName). When not set (Duplicate Tab without
        # Query), the copy uses the "Query{#}" scheme (Get-UniqueQueryName).
        [switch]$UseSourceName
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        $Source = $Script:Tabs | Where-Object { $_.Id -eq $SourceTabId } | Select-Object -First 1
        if ($null -eq $Source) {
            "Complete-DuplicateTab: source tab '{0}' no longer exists." -f $SourceTabId | Write-LogOutput -LogType WARNING
            return
        }

        # The duplicate is a new, unsaved query: the selected query is deliberately not copied.
        $DuplicateConfig = New-TabConfigFromTab -SourceTab $Source

        $NewTab = New-TabSession -RestoreFrom $DuplicateConfig -AutoConnect:$SourceConnected
        if ($null -eq $NewTab) {
            return
        }

        # Put the duplicate's name into its Display name field, made unique against the existing
        # saved queries so it never clashes with one already in the query list. The source tab
        # shares the same connection, so its loaded query list is the right set to check against.
        # For a duplicate *with* the query, base the name on the source query and bump the trailing
        # number ("Users" -> "Users1"); otherwise fall back to the "Query{#}" scheme.
        $ExistingQueryNames = @()
        try {
            foreach ($QueryEntry in @($Source.RunTimeData.QueryListCache.QueryList)) {
                if ($QueryEntry -is [System.Collections.IDictionary]) {
                    foreach ($QueryDisplayName in $QueryEntry.Values) {
                        if (![string]::IsNullOrWhiteSpace($QueryDisplayName)) {
                            $ExistingQueryNames += $QueryDisplayName.ToString()
                        }
                    }
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType WARNING
        }

        if ($UseSourceName) {
            # The source's own name: its selected query, the name proposed for it, or Query{#}.
            $UniqueQueryName = Get-IncrementedQueryName -BaseName (Get-TabName -TabSession $Source) -ExistingNames $ExistingQueryNames
        }
        else {
            $UniqueQueryName = Get-UniqueQueryName -ExistingNames $ExistingQueryNames -StartNumber $NewTab.OpenOrder
        }
        # The name the copy is proposed under: it names the tab and is suggested when it is saved.
        # Held on the tab rather than in a control, so nothing loaded later can clear it.
        $NewTab.ProposedQueryName = $UniqueQueryName

        # Hand the SQL to the new tab; its NavigationCompleted handler pushes it into Monaco once
        # the editor has loaded (pushing now would be dropped - the editor is not ready yet).
        if (![string]::IsNullOrEmpty($EditorText)) {
            $NewTab.PendingEditorText = $EditorText
            $NewTab.IsDirty = $true
        }
        Update-TabHeaderTitle -TabSession $NewTab

        # The duplicate is now the active tab. Move keyboard focus onto it so, when the duplicate was
        # triggered from the editor via Ctrl+Shift+K / Ctrl+T, focus does not stay stuck on the
        # source tab's now-hidden WebView2 (which would freeze every following shortcut).
        Set-ActiveTabEditorFocus

        "Duplicated tab '{0}' into a new tab named '{1}'." -f $Source.DisplayName, $UniqueQueryName | Write-LogOutput -LogType DEBUG
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
