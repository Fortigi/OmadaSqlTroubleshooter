function Open-QueryManagerForm {
    <#
    .SYNOPSIS
        Opens the query manager: every query object on the active tab's tenant, with details,
        history, create, open, rename and delete.

    .DESCRIPTION
        Modal, like the other windows of this application, with the completion poll timer suspended
        while it is open. Works on the active tab's connection, so it needs a connected tab.

        An action that should show something in the main window (opening a query in a tab, restoring a
        version from its history) asks the manager to close (Request-QueryManagerClose): a tab opened
        while a modal window is up cannot load its editor until that window is gone.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3})" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber)))

        if (-not $Script:ConnectionStatus) {
            "Connect to Omada to manage its queries." | Write-LogOutput -LogType WARNING
            return
        }

        $Script:QueryManagerCloseRequested = $false
        $Script:QueryManagerForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\QueryManagerForm.xaml")
        $Script:QueryManagerForm | Add-Member -NotePropertyName "Queries" -NotePropertyValue @() -Force
        $Script:QueryManagerForm | Add-Member -NotePropertyName "Ownership" -NotePropertyValue @{} -Force
        # The "Only my queries" filters start as the active tab has them; changing them here changes
        # only this window.
        $Script:QueryManagerForm.Elements.CheckBoxQueryManagerMyCreated.IsChecked = [bool]$Script:AppConfig.MyCreatedQueriesOnly
        $Script:QueryManagerForm.Elements.CheckBoxQueryManagerMyUpdated.IsChecked = [bool]$Script:AppConfig.MyUpdatedQueriesOnly
        $Script:QueryManagerForm.Definition.Owner = $Script:MainForm.Definition
        $Script:QueryManagerForm.Definition.Title = "Queries - {0}" -f ([System.Uri]::new($Script:AppConfig.BaseUrl)).Authority

        Import-EventObjects -ClassName "QueryManagerForm"
        Update-QueryManagerList -Refresh

        Suspend-WebViewCompletionPolling
        try {
            $Script:QueryManagerForm.State = "Open"
            [void]$Script:QueryManagerForm.Definition.ShowDialog()
        }
        finally {
            $Script:QueryManagerForm.State = "Closed"
            Resume-WebViewCompletionPolling
        }
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}

function Update-QueryManagerList {
    <#
    .SYNOPSIS
        Shows the query objects in the manager's grid, filtered; with -Refresh, reads them from the
        tenant first.

    .PARAMETER Refresh
        Read the list from the tenant. Without it, only the filter is applied again to the list
        already read - typing in the filter makes no request.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [switch]$Refresh
    )

    if ($Refresh) {
        $Private:Response = Invoke-SavedQueryRequest -Request (New-QueryManagerRequest -Kind "QueryObjectList" -Context @{ BaseUrl = $Script:AppConfig.BaseUrl })
        if (-not $Private:Response.Succeeded) {
            "Reading the queries failed: {0}" -f $Private:Response.Message | Write-ContainedErrorLog
            return
        }
        $Script:QueryManagerForm.Queries = @($Private:Response.Result.value | Where-Object { $null -ne $_ })
        $Script:QueryManagerForm.Ownership = Get-QueryManagerOwnership
    }

    $Private:Elements = $Script:QueryManagerForm.Elements
    $Private:All = @($Script:QueryManagerForm.Queries)
    $Private:MyCreated = [bool]$Private:Elements.CheckBoxQueryManagerMyCreated.IsChecked
    $Private:MyUpdated = [bool]$Private:Elements.CheckBoxQueryManagerMyUpdated.IsChecked
    $Private:Shown = @(Select-QueryManagerQuery -Query $Private:All -Filter $Private:Elements.TextBoxQueryFilter.Text -Ownership $Script:QueryManagerForm.Ownership `
            -UserName (Get-QueryManagerUserName -Needed ($Private:MyCreated -or $Private:MyUpdated)) -MyCreated $Private:MyCreated -MyUpdated $Private:MyUpdated `
            -View (Get-QueryManagerView))

    $Private:Table = ConvertTo-QueryManagerTable -Query $Private:Shown -Ownership $Script:QueryManagerForm.Ownership
    $Private:Elements.DataGridQueries.ItemsSource = $Private:Table.DefaultView
    if ($Refresh) {
        # From the whole list, once per read: a filter that shows fewer rows keeps the widths, and so
        # does a column the user widened.
        Update-DataGridColumnWidth -Grid $Private:Elements.DataGridQueries -Item @((ConvertTo-QueryManagerTable -Query $Private:All -Ownership $Script:QueryManagerForm.Ownership).DefaultView)
    }
    # "of" the queries in the view, before the text and "Only my queries" filters.
    $Private:InView = @($Private:All | Where-Object { Test-QueryManagerView -Query $_ -View (Get-QueryManagerView) })
    $Private:Elements.TextBlockQueryCount.Text = "{0} of {1} queries" -f $Private:Shown.Count, $Private:InView.Count
    Update-QueryManagerCommandState
}

function Get-QueryManagerUserName {
    <#
    .SYNOPSIS
        The signed-in user's name for the query manager's "Only my queries" filters.

    .DESCRIPTION
        The active tab knows it only while one of the main window's own filters is on: switching
        those off clears it. So the query manager reads it itself (Get-OmadaIdentityUserName) the first
        time one of its filters is on and the tab has none, and keeps it for as long as the window is
        open. Without the name the filters cannot apply; that is said once.

    .PARAMETER Needed
        A filter is on. Without one, no request is made.

    .OUTPUTS
        [string] The name, or "".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [bool]$Needed
    )

    # Asked once per window, an answer of "none" included, so a tenant that gives no name is not
    # asked - and the user not warned - again on every keystroke in the filter.
    if ($null -ne $Script:QueryManagerForm.PSObject.Properties["UserName"]) {
        return [string]$Script:QueryManagerForm.UserName
    }
    if (-not $Needed) {
        return ""
    }

    $Private:Name = [string]$Script:AppConfig.IdentityUserName
    if ([string]::IsNullOrWhiteSpace($Private:Name)) {
        try {
            $Private:Name = [string](Get-OmadaIdentityUserName)
        }
        catch {
            "Reading the user name failed: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
        }
    }

    if ([string]::IsNullOrWhiteSpace($Private:Name)) {
        "Your user name could not be read from Omada, so Only my queries cannot be applied." | Write-LogOutput -LogType WARNING
        $Private:Name = ""
    }
    $Script:QueryManagerForm | Add-Member -NotePropertyName "UserName" -NotePropertyValue $Private:Name -Force
    return $Private:Name
}

function Get-QueryManagerView {
    <#
    .SYNOPSIS
        Which queries the query manager's view selector shows: Active (not deleted, the default),
        Deleted, or All. Read from the selected item's Tag.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $Private:View = [string]$Script:QueryManagerForm.Elements.ComboBoxQueryManagerView.SelectedItem.Tag
    return $(if ($Private:View -in @("Active", "Deleted", "All")) { $Private:View } else { "Active" })
}

function Get-QueryManagerOwnership {
    <#
    .SYNOPSIS
        Who created and last changed each query, read from the tenant's "SQL Troubleshooting" view:
        the extra request the "Only my queries" filters and the Created by / Changed by columns need.

    .DESCRIPTION
        OData does not return those two fields; the view does (Get-QueryOwnership). A tenant without
        the view, or a view that cannot be read, gives no ownership: the columns stay empty and the
        filters cannot be applied, which is said once in the log rather than failing the list.

    .OUTPUTS
        [hashtable] query id -> @{ CreatedBy; ChangedBy }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    try {
        $Private:Rows = @(Get-SqlTroubleShooterView)
    }
    catch {
        "Reading the SQL Troubleshooting view failed: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
        $Private:Rows = @()
    }

    $Private:Ownership = Get-QueryOwnership -ViewRow $Private:Rows -Mapping $Script:RunTimeData.DataobjdlgAspxAttributeMapping
    if ($Private:Ownership.Count -eq 0) {
        "The SQL Troubleshooting view gave no rows: Created by, Changed by and the Only my queries filters are not available." | Write-LogOutput -LogType INFO
    }
    return $Private:Ownership
}

function Get-QueryManagerSelectedQuery {
    <#
    .SYNOPSIS
        The query selected in the manager's grid, as @{ DoId; DisplayName }, or $null with a hint.

    .DESCRIPTION
        The grid selects as the result grid does: whole rows from the row headers, single cells or
        ranges of cells, with Ctrl and Shift. The buttons act on one query, so the selection counts
        when every selected cell and row belongs to one and the same row; the cell with the focus
        counts when nothing is selected. A selection over several queries is refused with a hint
        rather than guessed at.

    .OUTPUTS
        [PSCustomObject] or $null.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # No hint: for the buttons' enabled state, which is worked out on every selection change.
        [switch]$Quiet
    )

    $Private:Rows = @(Get-DataGridSelectedRow -Grid $Script:QueryManagerForm.Elements.DataGridQueries | Where-Object { $null -ne $_.PSObject.Properties["Row"] })

    if ($Quiet) {
        return $(if ($Private:Rows.Count -eq 1) { ConvertFrom-QueryManagerRow -Row $Private:Rows[0].Row } else { $null })
    }
    if ($Private:Rows.Count -eq 0) {
        "Select a query first." | Write-LogOutput -LogType WARNING
        return $null
    }
    if ($Private:Rows.Count -gt 1) {
        "{0} queries are selected. Select cells or the row of one query for this command." -f $Private:Rows.Count | Write-LogOutput -LogType WARNING
        return $null
    }

    return ConvertFrom-QueryManagerRow -Row $Private:Rows[0].Row
}

function ConvertFrom-QueryManagerRow {
    <#
    .SYNOPSIS
        Reads the query id and name back from a row of the manager's table.

    .PARAMETER Row
        A DataRow of ConvertTo-QueryManagerTable.

    .OUTPUTS
        [PSCustomObject] @{ DoId; DisplayName }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        $Row
    )

    $Private:Name = if ($Row.Table.Columns.Contains("DisplayName")) { [string]$Row["DisplayName"] } else { $null }
    if ([string]::IsNullOrWhiteSpace($Private:Name) -and $Row.Table.Columns.Contains("Name")) {
        $Private:Name = [string]$Row["Name"]
    }

    return [PSCustomObject]@{
        DoId        = [string]$Row["Id"]
        DisplayName = $Private:Name
        Deleted     = $Row.Table.Columns.Contains("Deleted") -and [string]$Row["Deleted"] -eq "Yes"
    }
}

function Update-QueryManagerCommandState {
    <#
    .SYNOPSIS
        Enables the query manager's buttons that can act on the selection, and greys out the rest
        (Get-QueryManagerCommandState). Run on every selection change and after the list is shown.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    $Private:State = Get-QueryManagerCommandState -Query (Get-QueryManagerSelectedQuery -Quiet)
    $Private:Buttons = @{
        Open      = "ButtonOpenQueryObject"
        OpenInTab = "ButtonOpenQueryObjectInTab"
        Details   = "ButtonShowQueryObjectDetails"
        Rename    = "ButtonRenameQueryObject"
        Delete    = "ButtonDeleteQueryObject"
        Restore   = "ButtonRestoreQueryObject"
        Omada     = "ButtonOpenQueryObjectInOmada"
        OData     = "ButtonOpenQueryObjectOData"
    }
    foreach ($Private:Action in $Private:Buttons.Keys) {
        $Private:Button = $Script:QueryManagerForm.Elements.($Private:Buttons[$Private:Action])
        if ($null -ne $Private:Button) {
            $Private:Button.IsEnabled = $Private:State[$Private:Action]
        }
    }
}

function Get-QueryManagerCommandState {
    <#
    .SYNOPSIS
        Which of the query manager's actions can act on the selected query.

    .DESCRIPTION
          no single query selected   none of them (New and Refresh do not need one)
          a query                    everything but Restore
          a deleted query            Details and Restore. It cannot be opened, renamed or deleted
                                     until it is restored, and neither its Omada page nor its OData
                                     record can be found while it is deleted

    .PARAMETER Query
        The selected query (Get-QueryManagerSelectedQuery -Quiet), or $null.

    .OUTPUTS
        [hashtable] action -> [bool]
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Query
    )

    $Private:Selected = $null -ne $Query
    $Private:Active = $Private:Selected -and $Query.Deleted -ne $true
    return @{
        Open      = $Private:Active
        OpenInTab = $Private:Active
        Rename    = $Private:Active
        Delete    = $Private:Active
        Details   = $Private:Selected
        Omada     = $Private:Active
        OData     = $Private:Active
        Restore   = $Private:Selected -and -not $Private:Active
    }
}


function Request-QueryManagerClose {
    <#
    .SYNOPSIS
        Asks the query manager, and its detail window, to close as soon as control returns to them.

    .DESCRIPTION
        Called from inside nested modal windows (the history window opened from the details opened
        from the manager). Closing an outer window from there would pull it from under the inner one
        while its handler is still running, so each window closes itself instead, when the window it
        opened returns (Complete-QueryManagerChildWindow).

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    $Script:QueryManagerCloseRequested = $true
}

function Complete-QueryManagerChildWindow {
    <#
    .SYNOPSIS
        After a window opened from the manager or its details returns: closes this window too when a
        close was requested meanwhile.

    .PARAMETER Window
        The window that opened the child (the manager's or the details' Definition).

    .OUTPUTS
        [bool] $true when the window was closed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        $Window
    )

    if ($true -ne $Script:QueryManagerCloseRequested) {
        return $false
    }

    $Window.Close()
    return $true
}
