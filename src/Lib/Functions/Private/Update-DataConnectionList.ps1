function Update-DataConnectionList {
    <#
    .SYNOPSIS
    Refresh the data connection dropdown for the active tab.

    .DESCRIPTION
    Issue #90, slice A. This was the worst of the blocking list refreshes: THREE dependent round-trips
    on the UI thread - the view lookup's two, then the dataobjdlg.aspx page that actually holds the
    options - and it runs on connect and on tab materialisation, which is where the window visibly
    froze.

    All three now go to a worker as ONE job (Invoke-OmadaViewLookupPipeline), so there is one
    completion rather than three. That number is the point: between completions Set-ActiveTabContext
    can repoint $Script:MainForm.Elements onto a different tab, and issue #90 names that as the
    dominant risk of this whole slice.

    When a worker may not be used - a disconnected tab, a forced re-authentication, background
    requests switched off - the original synchronous path below runs unchanged.
    #>
    [CmdLetBinding()]
    param(
        [switch]$NotShowPopupWindow
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        if (!(Test-ConnectionRequirements)) {
            "Connection not ready" | Write-LogOutput -LogType DEBUG
            return
        }

        "Retrieve data connections" | Write-LogOutput -LogType DEBUG

        # The completion block is plain (never .GetNewClosure()) and reads everything it needs from
        # its arguments: by the time it runs, the user may be looking at another tab, and
        # -NotShowPopupWindow must be the value THIS call was made with.
        $Private:Pending = Start-SqlTroubleShooterViewLookup -IncludeDataObjectHtml -Context @{
            NotShowPopupWindow = [bool]$NotShowPopupWindow
        } -OnResultScriptBlock {
            param($Result, $CallerContext)

            if ($Result.RetryInline) {
                $Private:Inline = Get-DataConnectionPageInline
                Complete-DataConnectionListUpdate -DataObjectHtml $Private:Inline.Html -HasRows:$Private:Inline.HasRows -NotShowPopupWindow:$CallerContext.NotShowPopupWindow
                return
            }

            Complete-DataConnectionListUpdate -DataObjectHtml $Result.DataObjectHtml -HasRows:(@($Result.Rows).Count -gt 0) -NotShowPopupWindow:$CallerContext.NotShowPopupWindow
        }

        if ($null -ne $Private:Pending) {
            # Dispatched. Everything after the responses now happens in the completion block.
            return
        }

        # Not eligible for a worker, or none available: exactly the pre-#90 behaviour.
        $Private:Inline = Get-DataConnectionPageInline
        Complete-DataConnectionListUpdate -DataObjectHtml $Private:Inline.Html -HasRows:$Private:Inline.HasRows -NotShowPopupWindow:$NotShowPopupWindow
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}

function Get-DataConnectionPageInline {
    <#
    .SYNOPSIS
    Fetch the dataobjdlg.aspx page that holds the data connection options, on the UI thread.

    .DESCRIPTION
    The blocking path, preserved verbatim from before issue #90: look the view up, take the first
    row's data object id, and GET its page. One definition, used both when no worker was available
    and when a worker could not do the job.

    .OUTPUTS
    Hashtable @{ HasRows; Html }. HasRows is $false when the view holds nothing, which the original
    code treated differently from a failed page fetch - see Complete-DataConnectionListUpdate.
    #>
    [CmdLetBinding()]
    param()

    # Count, not a null check. A view that exists but holds nothing comes back as an empty array,
    # which is not $null - so the null check let it straight through. Nothing throws: this codebase
    # never enables Set-StrictMode (see ConvertTo-TabSessionConfig), so @()[0] is $null and so is the
    # id read off it. The request was then built as "dataobjdlg.aspx?DOID=" with no id at all, sent,
    # and its answer reported as "Failed to retrieve data connections!" - which disables the dropdown
    # and the schema button. A wasted round-trip producing the wrong outcome, where the right one is
    # to leave the list alone, as the original code did for this case.
    $Private:SqlQueryViewContents = @(Get-SqlTroubleShooterView)
    if ($Private:SqlQueryViewContents.Count -eq 0) {
        return @{ HasRows = $false; Html = $null }
    }

    $Script:RunTimeData.RestMethodParam.Uri = "{0}/dataobjdlg.aspx?DOID={1}" -f $Script:AppConfig.BaseUrl, $Private:SqlQueryViewContents[0].$($Script:RunTimeData.DataobjdlgAspxAttributeMapping.SqlQueryDoId)
    $Script:RunTimeData.RestMethodParam.Body = $null
    $Script:RunTimeData.RestMethodParam.Method = "GET"
    return @{ HasRows = $true; Html = (Invoke-OmadaPSWebRequestWrapper) }
}

function Complete-DataConnectionListUpdate {
    <#
    .SYNOPSIS
    Everything that happens once the data connection page is in hand: rebuild the dropdown, restore
    the selection, and enable the controls that depend on it.

    .DESCRIPTION
    Split out of Update-DataConnectionList by issue #90 so the same work runs whether the page
    arrived synchronously or from a background worker. It touches WPF elements, so it is UI thread
    only - which it always is: the background path reaches it from the completion poll timer, with
    the owning tab already made active by Set-ActiveTabContext.

    .PARAMETER DataObjectHtml
    The dataobjdlg.aspx response, or $null when it could not be retrieved.

    .PARAMETER HasRows
    Whether the "SQL Troubleshooting" view held any rows. This is deliberately separate from a null
    page: the original code only entered its whole body when the view returned rows, so a tenant
    without them left the dropdown untouched and said nothing, whereas a FAILED page fetch warned and
    disabled the controls. Two different outcomes that both arrive here as a null page, so the
    distinction has to travel alongside it rather than be inferred.

    .PARAMETER NotShowPopupWindow
    Suppress the "Updating Data Connections..." popup, as the auto-connect paths always have.
    #>
    [CmdLetBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'SetInitialConnection', Justification = 'The variable is used, but script analyzer does not recognize it')]
    param(
        $DataObjectHtml,

        [switch]$HasRows,

        [switch]$NotShowPopupWindow
    )

    try {
        $Private:Result = $DataObjectHtml

        if (-not $HasRows) {
            "The SQL Troubleshooting view returned no rows; leaving the data connection list as it is." | Write-LogOutput -LogType DEBUG
            return
        }

        if ($null -eq $Private:Result) {
            "Failed to retrieve data connections! Data connection cannot be changed!" | Write-LogOutput -LogType WARNING
            $Script:MainForm.Elements.ComboBoxSelectDataConnection.IsEnabled = $false
            $Script:MainForm.Elements.ButtonShowSqlSchema.IsEnabled = $false
            return
        }

        if (!$NotShowPopupWindow) {
            $UpdateDataConnectionsWindow = Show-PopupWindow -Message "Updating Data Connections..."
        }

        $SelectedDataConnection = $Script:MainForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content
        "Stored current selected data connection (if not empty): {0}" -f $SelectedDataConnection | Write-LogOutput -LogType DEBUG
        $Script:MainForm.Elements.ComboBoxSelectDataConnection.Items.Clear()

        $SetInitialConnection = $true
        foreach ($DataConnectionDisplayName in (Get-DataConnectionOptionList -Html $Private:Result)) {
            if ($DataConnectionDisplayName -notin $Script:MainForm.Elements.ComboBoxSelectDataConnection.Items.Content) {
                "Add data connection {0}" -f $DataConnectionDisplayName | Write-LogOutput -LogType DEBUG
                $ComboBoxDataConnectionItem = New-Object System.Windows.Controls.ComboBoxItem
                $ComboBoxDataConnectionItem.Content = $DataConnectionDisplayName
                $Script:MainForm.Elements.ComboBoxSelectDataConnection.Items.Add($ComboBoxDataConnectionItem) | Out-Null
                if ($null -ne $SelectedDataConnection -and $SelectedDataConnection -eq $DataConnectionDisplayName) {
                    "Set connection {0} as selected data connection" -f $DataConnectionDisplayName | Write-LogOutput -LogType DEBUG
                    $Script:MainForm.Elements.ComboBoxSelectDataConnection.SelectedItem = $ComboBoxDataConnectionItem
                    $SetInitialConnection = $false
                }
            }
        }

        if ($SetInitialConnection) {
            "Set initial data connection to OISES" | Write-LogOutput -LogType DEBUG
            $Script:MainForm.Elements.ComboBoxSelectDataConnection.SelectedItem = $Script:MainForm.Elements.ComboBoxSelectDataConnection.Items | Where-Object { $_.Content -like "OISES -*" }
        }

        $ComboBoxDataConnectionSelectedItem = $Script:MainForm.Elements.ComboBoxSelectDataConnection.SelectedItem
        $ComboBoxDataConnectionItems = $Script:MainForm.Elements.ComboBoxSelectDataConnection.Items | Sort-Object
        $Script:MainForm.Elements.ComboBoxSelectDataConnection.Items?.Clear()
        foreach ($Item in $ComboBoxDataConnectionItems) {
            $Script:MainForm.Elements.ComboBoxSelectDataConnection.Items.Add($Item) | Out-Null
        }
        if ($null -ne $ComboBoxDataConnectionSelectedItem) {
            $Script:MainForm.Elements.ComboBoxSelectDataConnection.SelectedItem = $Script:MainForm.Elements.ComboBoxSelectDataConnection.Items | Where-Object { $_.Content -eq $ComboBoxDataConnectionSelectedItem.Content }
        }

        $Script:MainForm.Elements.TextBoxDisplayName.IsEnabled = $true
        $Script:MainForm.Elements.ComboBoxSelectDataConnection.IsEnabled = $true
        $Script:MainForm.Elements.ButtonShowSqlSchema.IsEnabled = $true

        "{0} data connections processed!" -f ($Script:MainForm.Elements.ComboBoxSelectDataConnection.Items | Measure-Object).Count | Write-LogOutput

        if ($null -ne $UpdateDataConnectionsWindow) {
            $UpdateDataConnectionsWindow.Close()
        }
    }
    catch {
        # Contained: this is reached from the completion poll timer, where a terminating log would
        # unwind into the timer's own Tick handler rather than into anything that can act on it.
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}
