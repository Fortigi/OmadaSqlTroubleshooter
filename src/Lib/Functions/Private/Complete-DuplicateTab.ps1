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
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        $Source = $Script:Tabs | Where-Object { $_.Id -eq $SourceTabId } | Select-Object -First 1
        if ($null -eq $Source) {
            "Complete-DuplicateTab: source tab '{0}' no longer exists." -f $SourceTabId | Write-LogOutput -LogType WARNING
            return
        }

        # New-TabSession -RestoreFrom expects the password as a DPAPI-protected string (it decrypts
        # it back for the password box), so re-encrypt the source's live plaintext password here.
        $Password = $null
        $SourcePassword = $Source.Elements.TextBoxPassword.Password
        if (![string]::IsNullOrWhiteSpace($SourcePassword)) {
            $Password = $SourcePassword | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
        }

        $DuplicateConfig = [PSCustomObject]@{
            Id                    = (New-Guid).Guid
            DisplayName           = $null
            BaseUrl               = $Source.AppConfig.BaseUrl
            # Deliberately NOT copied - the duplicate is a new, unsaved query.
            CurrentSqlQuery       = [PSCustomObject]@{ DoId = $null; DisplayName = $null; FullName = $null }
            LastAuthentication    = $Source.AppConfig.LastAuthentication
            UserName              = $Source.AppConfig.UserName
            Password              = $Password
            EntraApplicationIdUri = $Source.AppConfig.EntraApplicationIdUri
            EntraIdTenantId       = $Source.AppConfig.EntraIdTenantId
            MyCreatedQueriesOnly  = [bool]$Source.AppConfig.MyCreatedQueriesOnly
            MyUpdatedQueriesOnly  = [bool]$Source.AppConfig.MyUpdatedQueriesOnly
            SavePassword          = [bool]$Source.Elements.CheckboxSavePassword.IsChecked
            IdentityUserName      = $Source.AppConfig.IdentityUserName
            CurrentDataConnection = $Source.AppConfig.CurrentDataConnection
        }

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
            $SourceName = $Source.Elements.TextBoxDisplayName.Text
            if ([string]::IsNullOrWhiteSpace($SourceName)) {
                $SourceName = $Source.DisplayName
            }
            $UniqueQueryName = Get-IncrementedQueryName -BaseName $SourceName -ExistingNames $ExistingQueryNames
        }
        else {
            $UniqueQueryName = Get-UniqueQueryName -ExistingNames $ExistingQueryNames -StartNumber $NewTab.OpenOrder
        }
        $NewTab.Elements.TextBoxDisplayName.Text = $UniqueQueryName
        # Also re-apply it once the tab has finished loading/connecting: a connected duplicate runs
        # Update-QueryList during auto-connect, which clears the Display name field, so the tab's
        # NavigationCompleted handler restores it from PendingDisplayName as the final step.
        $NewTab.PendingDisplayName = $UniqueQueryName

        # Hand the SQL to the new tab; its NavigationCompleted handler pushes it into Monaco once
        # the editor has loaded (pushing now would be dropped - the editor is not ready yet).
        if (![string]::IsNullOrEmpty($EditorText)) {
            $NewTab.PendingEditorText = $EditorText
            $NewTab.IsDirty = $true
        }
        Update-TabHeaderTitle -TabSession $NewTab

        "Duplicated tab '{0}' into a new tab named '{1}'." -f $Source.DisplayName, $UniqueQueryName | Write-LogOutput -LogType DEBUG
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
