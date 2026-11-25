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
    }

    $Private:All = @($Script:QueryManagerForm.Queries)
    $Private:Shown = @(Select-QueryManagerQuery -Query $Private:All -Filter $Script:QueryManagerForm.Elements.TextBoxQueryFilter.Text)

    # Columns are generated from the table, so they follow whatever fields the tenant returns.
    $Private:Table = ConvertTo-QueryManagerTable -Query $Private:Shown
    $Script:QueryManagerForm.Elements.DataGridQueries.ItemsSource = $Private:Table.DefaultView
    $Script:QueryManagerForm.Elements.TextBlockQueryCount.Text = "{0} of {1} queries" -f $Private:Shown.Count, $Private:All.Count
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
    param()

    $Private:Rows = @(Get-DataGridSelectedRow -Grid $Script:QueryManagerForm.Elements.DataGridQueries | Where-Object { $null -ne $_.PSObject.Properties["Row"] })

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
