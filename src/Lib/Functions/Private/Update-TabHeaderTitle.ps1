function Update-TabHeaderTitle {
    <#
    .SYNOPSIS
    Refreshes a tab's header text from its current state.

    .DESCRIPTION
    Builds the header as:
      <query name>[*] - <data connection> - <tenant> [- No connection]
    where <query name> comes from Get-TabName (without its DoId), "*" is appended when the tab has
    unsaved query changes, <data connection> is the tab's data connection name without its DoId
    (omitted when empty), <tenant> is the tenant authority (omitted when no URL is configured), and
    "No connection" is appended only when the tab is not connected. Reads from the tab's own
    Elements/AppConfig so it is correct for any tab; the connected flag uses the live global for the
    active tab and the tab's stored flag otherwise. Also refreshes the application window title
    (Update-ApplicationTitle) when the tab being updated is the active one.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession
    )
    try {
        # Logging the full $PSBoundParameters here would dump the entire $TabSession object graph
        # (WPF elements, AppConfig) into the trace log - log a stable identifier instead.
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ("TabSession={0} ({1})" -f $TabSession.Id, $TabSession.DisplayName)))

        $BaseName = Get-TabName -TabSession $TabSession

        # Trace genuine renames so the log shows when (and how) a tab's name changed. Guarded by
        # HeaderInitialized so the very first header paint (default name -> derived name at tab
        # creation) is not reported as a rename.
        $PreviousName = $TabSession.DisplayName
        if ($TabSession.HeaderInitialized -and ![string]::IsNullOrWhiteSpace($PreviousName) -and $PreviousName -ne $BaseName) {
            "Tab renamed from '{0}' to '{1}' (Id: {2})" -f $PreviousName, $BaseName, $TabSession.Id | Write-LogOutput -LogType DEBUG
        }

        $TabSession.DisplayName = $BaseName
        $TabSession.HeaderInitialized = $true

        $Name = if ($TabSession.IsDirty) { "{0}*" -f $BaseName } else { $BaseName }

        # The active tab's connected state lives on the live global; other tabs carry their own
        # stored flag (kept in sync by Set-ActiveTabContext / Set-SqlConnectionState).
        $Connected = if ($TabSession.Id -eq $Script:ActiveTabId) { [bool]$Script:ConnectionStatus } else { [bool]$TabSession.ConnectionStatus }

        # Format: "<query name>[*] - <data connection> - <tenant> [- No connection]". The data
        # connection and tenant come from the tab's own config, so they show even when the tab is not
        # (yet) connected; the connection state is appended only when the tab is NOT connected.
        $Parts = [System.Collections.Generic.List[string]]::new()
        $Parts.Add($Name)

        # Data connection (database) name WITHOUT its DoId. Prefer the tab's parsed config (already
        # id-free); fall back to the selected combo item with its trailing " - <DoId>" stripped.
        $Connection = $null
        if ($null -ne $TabSession.AppConfig.CurrentDataConnection) {
            $Connection = $TabSession.AppConfig.CurrentDataConnection.DisplayName
        }
        if ([string]::IsNullOrWhiteSpace($Connection) -and $null -ne $TabSession.Elements.ComboBoxSelectDataConnection.SelectedItem) {
            $Connection = ([string]$TabSession.Elements.ComboBoxSelectDataConnection.SelectedItem.Content) -replace "\s*-\s*\d+\s*$", ""
        }
        if (![string]::IsNullOrWhiteSpace($Connection)) {
            $Connection = $Connection.ToString().Trim()
            if ($Connection -ne "-" -and $Connection -ne "0" -and $Connection -ne "- 0") {
                $Parts.Add($Connection)
            }
        }

        # Tenant (authority) only when a URL is configured.
        $Tenant = $null
        if (![string]::IsNullOrWhiteSpace($TabSession.AppConfig.BaseUrl)) {
            try {
                $Tenant = ([System.Uri]::new($TabSession.AppConfig.BaseUrl)).Authority
            }
            catch {
                $Tenant = $TabSession.AppConfig.BaseUrl
            }
        }
        if (![string]::IsNullOrWhiteSpace($Tenant)) {
            $Parts.Add($Tenant.Trim())
        }

        # Connection state ONLY when there is no connection.
        if (-not $Connected) {
            $Parts.Add("No connection")
        }

        $Title = $Parts -join " - "

        # Header content is a Grid (see New-TabHeaderControl): child 0 is the title TextBlock.
        $TabSession.TabItem.Header.Children[0].Text = $Title
        $TabSession.TabItem.ToolTip = $Title

        # The application window title mirrors the active tab; refresh it whenever the active tab's
        # header changes. This is what keeps the title bar live, not only updated on connect.
        if ($TabSession.Id -eq $Script:ActiveTabId) {
            Update-ApplicationTitle
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
