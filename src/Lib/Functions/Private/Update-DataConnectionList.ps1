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

            # Filtered, not just wrapped: @($null).Count is 1, so a plain @($Result.Rows).Count -gt 0
            # answers "yes, there are rows" for no rows at all - and the renderer then reports a
            # failed fetch and disables the dropdown. The pipeline normalises its own Rows, but the
            # completion's other paths pass $null deliberately, so this has to be honest about that.
            Complete-DataConnectionListUpdate -DataObjectHtml $Result.DataObjectHtml -HasRows:(@($Result.Rows | Where-Object { $null -ne $_ }).Count -gt 0) -NotShowPopupWindow:$CallerContext.NotShowPopupWindow
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
    # Filtered as well as wrapped. Get-SqlTroubleShooterView normalises its own result now, but this
    # is the third place in this change where @($null).Count -eq 1 turned no rows into one - so the
    # count is taken over something that cannot contain a null rather than trusting the shape.
    $Private:SqlQueryViewContents = @(Get-SqlTroubleShooterView | Where-Object { $null -ne $_ })
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
            # Reached from the completion poll timer since #101, which steps into the tab the work
            # was started for before invoking the completion - so the default active tab is the
            # right one, and a refresh started on tab A cannot write into tab B's status bar.
            # No -Render: see Update-QueryList. This one is reached from the completion poll timer
            # itself since #101, so pumping here would re-enter the very timer that invoked it.
            Set-TabStatusMessage -Message "Updating data connections..."
        }

        # try/finally around everything after the status message is written. The reset used to sit on
        # the success path only, so anything that threw while rebuilding or sorting the items left the
        # bar claiming an update was still running for the rest of the session - the catch below would
        # log it and the user would be looking at progress text over work that had stopped.
        try {
            $SelectedDataConnection = $Script:MainForm.Elements.ComboBoxSelectDataConnection.SelectedItem.Content
            "Stored current selected data connection (if not empty): {0}" -f $SelectedDataConnection | Write-LogOutput -LogType DEBUG
            $Script:MainForm.Elements.ComboBoxSelectDataConnection.Items.Clear()

            $SetInitialConnection = $true

            # Filtered here, where the dropdown is built, because the dropdown is the single definition
            # of which databases exist: Get-DataConnectionOptionText, Resolve-DataConnectionReference,
            # Push-SqlDatabaseNameList and Update-SqlSchemaDatabaseTree all read it back, so one filter
            # covers the tree, the editor's name list and name resolution (issue #165).
            #
            # Get-OmadaIngestionSetting answers from cache and never makes a request, so the FIRST build
            # on a session filters nothing - it does not know the flag yet. That is the ordering the
            # issue asks for: retrieve as before, then filter. Remove-FilteredDataConnectionItem applies
            # it when the probe answers, and every later build on the same session filters here.
            foreach ($DataConnectionDisplayName in (Remove-UnusedDataConnection -OptionList (Get-DataConnectionOptionList -Html $Private:Result) -IngestionEnabled (Get-OmadaIngestionSetting))) {
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

            # The list IS the database level of the schema tree and the list of names the editor
            # recognises between brackets (issue #158), so both are brought up to date here rather
            # than waiting for the next schema response. This is the moment the list is known to be
            # current, and it closes the ordering gap: the schema can land before the connection
            # list does, and neither of these may trigger a request of its own to catch up.
            Update-SqlSchemaDatabaseTree
            Push-SqlDatabaseNameList

            # Issue #165, and last in this block on purpose: both dispatch and return, so neither
            # blocks the render path, and an exception in either cannot cost the list that has just
            # been built.
            #
            # The probe learns the tenant's ingestion flag - one request, cached per session, so this
            # is free on every connect after the first. The preload asks for every database's schema on
            # a worker, which is what makes a schema node populated before the user clicks it.
            #
            # The preload waits for the probe. The connections the filter removes answer 500 on a live
            # tenant, and preloading them cost a synchronous retry each and switched background requests
            # off. So the ORDER of these two calls matters: the probe has to be on the completion queue
            # when the preload checks, so the preload declines and the probe's completion starts it
            # after the prune. When the answer is already cached no probe is dispatched, and the
            # preload runs here as before. Nothing else waits - the list is already on screen.
            Start-OmadaIngestionSettingProbe
            Start-SqlSchemaPreload
        }
        finally {
            if (!$NotShowPopupWindow) {
                Reset-TabStatusMessage
            }
        }
    }
    catch {
        # Contained: this is reached from the completion poll timer, where a terminating log would
        # unwind into the timer's own Tick handler rather than into anything that can act on it.
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}

function Remove-FilteredDataConnectionItem {
    <#
    .SYNOPSIS
    Prunes the data connections the ingestion flag rules out from the dropdown, after the fact.

    .DESCRIPTION
    Issue #165. The dropdown is built before the ingestion probe has answered - deliberately, so the
    list appears as quickly as it always did - which leaves the filter to be applied when the answer
    arrives. This is that second pass, and the only caller is the probe's completion.

    ONLY THE DROPDOWN IS PRUNED, which is the reason the whole feature needs so little code:
    Update-SqlSchemaDatabaseTree removes the node of any connection that has left the dropdown, and
    Push-SqlDatabaseNameList re-pushes the names the editor may complete - both read the dropdown back.
    So one prune reconciles the tree and the editor's name list, and there is no second definition of
    "which databases exist" to keep in step with this one.

    Returns without touching anything when the filter keeps everything, so a tenant with ingestion off
    - or one whose flag could not be read - pays nothing and sees no spurious reconcile.

    UI thread only, like everything else in this file: the poll timer invokes the probe's completion
    with the owning tab already made active.

    .OUTPUTS
    None.
    #>
    [CmdLetBinding()]
    param()

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

        $Private:ComboBox = $Script:MainForm.Elements.ComboBoxSelectDataConnection
        if ($null -eq $Private:ComboBox -or $Private:ComboBox.Items.Count -eq 0) {
            return
        }

        $Private:Current = @($Private:ComboBox.Items | ForEach-Object { [string]$_.Content })
        $Private:Kept = @(Remove-UnusedDataConnection -OptionList $Private:Current -IngestionEnabled (Get-OmadaIngestionSetting))

        if ($Private:Kept.Count -eq $Private:Current.Count) {
            return
        }

        # Read before the removals: removing the selected item clears SelectedItem, so asking
        # afterwards cannot tell "the selection was filtered away" from "there was no selection".
        $Private:SelectedContent = [string]$Private:ComboBox.SelectedItem.Content

        # Taken off a snapshot because the collection is modified in the loop.
        foreach ($Private:Item in @($Private:ComboBox.Items)) {
            if ([string]$Private:Item.Content -notin $Private:Kept) {
                $Private:ComboBox.Items.Remove($Private:Item)
            }
        }

        # A user whose selected connection has just been filtered away must not be left with a dropdown
        # pointing at nothing. Falls back the same way the initial build does - OISES first, then
        # whatever is left - and the resulting SelectionChanged is the same event the initial build
        # raises, so nothing downstream sees a case it has not already handled.
        if ($Private:SelectedContent -notin $Private:Kept) {
            $Private:ComboBox.SelectedItem = $Private:ComboBox.Items | Where-Object { $_.Content -like "OISES -*" }
            if ($null -eq $Private:ComboBox.SelectedItem) {
                $Private:ComboBox.SelectedItem = $Private:ComboBox.Items | Select-Object -First 1
            }
        }

        Update-SqlSchemaDatabaseTree
        Push-SqlDatabaseNameList
    }
    catch {
        # Contained: reached from the completion poll timer. A failed prune leaves a connection in the
        # list that does not work, which is exactly what the application did before this feature.
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}
