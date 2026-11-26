function Invoke-QueryManagerAction {
    <#
    .SYNOPSIS
        Carries out one of the query manager's buttons on its selected query.

    .DESCRIPTION
          Create   New-SqlQueryObject; the list is read again, and the user is asked where to open
                   it: in this tab, in a new tab, or not.
          Open       Open-SqlQueryInActiveTab: in place of the active tab's query, after offering to
                     save its unsaved changes. The manager then closes so the tab can be seen - but
                     only when the query was opened; cancelled, or with the tab not connected, it
                     stays open.
          OpenInTab  Open-SqlQueryInTab, then the manager closes the same way - only when a tab was
                     opened. At the tab limit New-TabSession refuses with a warning, and closing the
                     manager then would only lose the user's place.
          Omada    Open-OmadaQueryObject: the query's own page in Omada, in the default browser.
          OData    Open-OmadaQueryObject -Kind OData: the query's OData record, in the default browser.
          Details  Open-QueryDetailForm; afterwards the list is read again (it may have been renamed),
                   unless something there asked the manager to close.
          Rename   Rename-SqlQuery for that query; the list is read again.
          Delete   Remove-SavedSqlQuery for that query; the list is read again.
          Restore  Restore-SqlQueryObject for a deleted query; the list is read again.

    .PARAMETER Action
        Which button.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Create", "Open", "OpenInTab", "Details", "Rename", "Delete", "Restore", "Omada", "OData")]
        [string]$Action
    )

    if ($Action -eq "Create") {
        Invoke-QueryManagerCreate
        return
    }

    $Private:Query = Get-QueryManagerSelectedQuery
    if ($null -eq $Private:Query) {
        return
    }

    if ($Action -in @("Open", "OpenInTab", "Omada", "OData")) {
        Invoke-QueryManagerOpenAction -Action $Action -Query $Private:Query
        return
    }

    # Details, rename, delete and restore can change the list; it is read again after any of them
    # that happened.
    $Private:Changed = switch ($Action) {
        "Details" {
            $null = Open-QueryDetailForm -DoId $Private:Query.DoId -DisplayName $Private:Query.DisplayName -Owner $Script:QueryManagerForm.Definition
            -not (Complete-QueryManagerChildWindow -Window $Script:QueryManagerForm.Definition)
        }
        "Rename" { $null -ne (Rename-SqlQuery -DoId $Private:Query.DoId -DisplayName $Private:Query.DisplayName) }
        "Delete" { [bool](Remove-SavedSqlQuery -DoId $Private:Query.DoId -DisplayName $Private:Query.DisplayName) }
        "Restore" { [bool](Restore-SqlQueryObject -DoId $Private:Query.DoId -DisplayName $Private:Query.DisplayName) }
    }
    if ($Private:Changed -eq $true) {
        Update-QueryManagerList -Refresh
    }
}

function Invoke-QueryManagerOpenAction {
    <#
    .SYNOPSIS
        The query manager's opening actions for one query: in the active tab, in a new tab, its page
        in Omada, its OData record. Opening it in a tab closes the manager - but only when the query
        was opened (see Invoke-QueryManagerAction).

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Open", "OpenInTab", "Omada", "OData")]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        $Query
    )

    switch ($Action) {
        "Omada" { Open-OmadaQueryObject -DoId $Query.DoId; return }
        "OData" { Open-OmadaQueryObject -DoId $Query.DoId -Kind OData; return }
    }

    $Private:Tab = if ($Action -eq "Open") {
        Open-SqlQueryInActiveTab -DoId $Query.DoId -DisplayName $Query.DisplayName
    }
    else {
        Open-SqlQueryInTab -DoId $Query.DoId -DisplayName $Query.DisplayName
    }
    if ($null -ne $Private:Tab) {
        $Script:QueryManagerForm.Definition.Close()
    }
}

function Invoke-QueryManagerCreate {
    <#
    .SYNOPSIS
        The query manager's New: create a query, show it in the list, and offer to open it.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    $Private:Names = @($Script:QueryManagerForm.Queries | ForEach-Object { [string]$_.DisplayName })
    $Private:Created = New-SqlQueryObject -ExistingNames $Private:Names
    if ($null -eq $Private:Created) {
        return
    }

    Update-QueryManagerList -Refresh

    # Where to open it: in place of the active tab's query (with that tab's usual save prompt), in a
    # new tab, or not at all. The manager closes once it is open, and stays when it is not.
    $Private:Choice = Open-ChoiceForm -Title "Query created" -Message ("Query '{0}' was created. Open it?" -f $Private:Created.DisplayName) `
        -LeftButtonText "In this tab" -RightButtonText "In a new tab" -ExtraButtonText "Not now" `
        -LeftButtonReturnValue "Open" -RightButtonReturnValue "OpenInTab" -ExtraButtonReturnValue "None"
    if ($Private:Choice -in @("Open", "OpenInTab")) {
        Invoke-QueryManagerOpenAction -Action $Private:Choice -Query $Private:Created
    }
}
