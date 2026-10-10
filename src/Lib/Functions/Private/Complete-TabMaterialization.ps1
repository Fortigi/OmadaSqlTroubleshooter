function Complete-TabMaterialization {
    <#
    .SYNOPSIS
    Performs the heavy, deferred part of bringing a tab to life: the (optional) reconnect and the
    WebView2/Monaco editor initialization. Split out of New-TabSession so restored tabs can be
    created cheaply (header + fields only) and only pay this cost when first viewed - see
    Restore-TabSessions (materializes just the active tab) and MainForm.Elements.TabControlSessions
    (materializes a deferred tab on its first real selection).

    .DESCRIPTION
    Idempotent: returns immediately if the tab is already materialized. Reads/writes the active-tab
    globals ($Script:AppConfig, $Script:MainForm.Elements, $Script:RunTimeData, $Script:RunTimeConfig),
    so it activates the tab first if it is not already the active context. PendingAutoConnect carries
    the restore-time "reconnect all?" answer for this tab; it is honoured once and then cleared.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ("TabSession={0} ({1})" -f $TabSession.Id, $TabSession.DisplayName)))

        if ($TabSession.IsMaterialized) {
            return
        }

        # The connect sequence and Initialize-WebViewForTab below act on the active-tab globals, so
        # make sure this tab is the active context. In the normal paths (New-TabSession's eager
        # branch, or the tab-switch handler) it already is, so this is just a safety net.
        if ($Script:ActiveTabId -ne $TabSession.Id) {
            Set-ActiveTabContext -TabSession $TabSession
        }

        if ($TabSession.PendingAutoConnect -and (Test-OmadaConnection)) {
            # Mirror the interactive Connect button (which sets ReconnectStatus = 2 before
            # connecting): Test-ConnectionSettings below treats ReconnectStatus -le 1 as "force
            # disconnected", so without this a successful reconnect is torn down again - leaving the
            # restored tab authenticated under the hood but shown as disconnected, with an empty
            # editor and nothing selected.
            $Script:RunTimeConfig.ReconnectStatus = 2

            if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentSqlQuery.DoId)) {
                $ComboBoxSelectQueryItem = $Script:MainForm.Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -like "*$($Script:AppConfig.CurrentSqlQuery.DoId)" }
                if ($null -eq $ComboBoxSelectQueryItem) {
                    $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                    $ComboBoxSelectQueryItem.Content = $Script:AppConfig.CurrentSqlQuery.FullName
                    $Script:MainForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                    $Script:RunTimeData.CurrentSqlQuery.DisplayName = $Script:AppConfig.CurrentSqlQuery.DisplayName
                    $Script:MainForm.Elements.TextBoxDisplayName.Text = $Script:RunTimeData.CurrentSqlQuery.DisplayName
                }
                # SelectedItem (not SelectedValue) - Set-EditorValue's own guard checks SelectedItem
                # directly, and Update-QueryList (the proven-working path, e.g. from clicking
                # Refresh) also sets SelectedItem for exactly this reason.
                $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem = $ComboBoxSelectQueryItem
            }

            if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnection.FullName)) {
                Set-DataConnection
            }
            Test-ConnectionSettings
            Test-ConnectionButton

            # The full data connection dropdown for this tab - auto-connect (restore / duplicate)
            # otherwise only ever showed the single current connection set by Set-DataConnection above.
            #
            # AFTER the connect, as the Connect button does it. It used to come first, while the tab
            # still counted as disconnected, and a disconnected tab may not use a background worker -
            # so the list's three requests ran one after another on the UI thread, about 2.3 s of
            # frozen window on a cloud PC. Connected, the list goes to a worker, and its completion
            # runs the ODW ingestion probe and the schema preload as it does after the Connect button.
            #
            # A tab that did not connect still gets its list, synchronously, as before.
            Update-DataConnectionList -NotShowPopupWindow

            # Connected-only work, now that the tab really is connected: the active connection's
            # IntelliSense schema (the query selection above ran while the tab was still disconnected,
            # and Get-SqlSchemaObject refuses that), the ingestion probe and the preload. The list
            # completion asks for the last two as well; both are idempotent (cached answer, in-flight
            # check on the queue), so whichever comes second costs nothing. Probe first: the preload
            # declines while the probe is pending, and the probe's completion starts it after the
            # filter is applied.
            if ($Script:ConnectionStatus) {
                Get-SqlSchemaObject
                Start-OmadaIngestionSettingProbe
                Start-SqlSchemaPreload
            }
        }
        else {
            Set-SqlConnectionState -Status $false
        }

        $TabSession.IsMaterialized = $true
        $TabSession.PendingAutoConnect = $false

        Initialize-WebViewForTab -TabSession $TabSession
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
