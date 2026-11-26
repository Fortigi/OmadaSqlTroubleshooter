function Invoke-QueryManagerAction {
    <#
    .SYNOPSIS
        Carries out one of the query manager's buttons on its selected query.

    .DESCRIPTION
          Create   New-SqlQueryObject; the list is read again and the new query selected, and the user
                   is offered to open it in a tab.
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

    .PARAMETER Action
        Which button.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Create", "Open", "OpenInTab", "Details", "Rename", "Delete", "Omada", "OData")]
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

    switch ($Action) {
        "Open" {
            if ($null -ne (Open-SqlQueryInActiveTab -DoId $Private:Query.DoId -DisplayName $Private:Query.DisplayName)) {
                $Script:QueryManagerForm.Definition.Close()
            }
        }
        "OpenInTab" {
            if ($null -ne (Open-SqlQueryInTab -DoId $Private:Query.DoId -DisplayName $Private:Query.DisplayName)) {
                $Script:QueryManagerForm.Definition.Close()
            }
        }
        "Omada" {
            Open-OmadaQueryObject -DoId $Private:Query.DoId
        }
        "OData" {
            Open-OmadaQueryObject -DoId $Private:Query.DoId -Kind OData
        }
        "Details" {
            Open-QueryDetailForm -DoId $Private:Query.DoId -DisplayName $Private:Query.DisplayName -Owner $Script:QueryManagerForm.Definition
            if (-not (Complete-QueryManagerChildWindow -Window $Script:QueryManagerForm.Definition)) {
                Update-QueryManagerList -Refresh
            }
        }
        "Rename" {
            if ($null -ne (Rename-SqlQuery -DoId $Private:Query.DoId -DisplayName $Private:Query.DisplayName)) {
                Update-QueryManagerList -Refresh
            }
        }
        "Delete" {
            if (Remove-SavedSqlQuery -DoId $Private:Query.DoId -DisplayName $Private:Query.DisplayName) {
                Update-QueryManagerList -Refresh
            }
        }
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

    $Private:Open = Open-ChoiceForm -Title "Query created" -Message ("Query '{0}' was created. Open it in a tab?" -f $Private:Created.DisplayName) -LeftButtonText "Open" -RightButtonText "Not now"
    if ($Private:Open -eq $true -and $null -ne (Open-SqlQueryInTab -DoId $Private:Created.DoId -DisplayName $Private:Created.DisplayName)) {
        $Script:QueryManagerForm.Definition.Close()
    }
}
