#Requires -Version 7.0
# The window itself needs WPF; what it does with its data does not.

BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManager.Shared.ps1")
    . (Join-Path $Script:QmPrivatePath "Open-QueryManagerForm.ps1")
    . (Join-Path $Script:QmPrivatePath "Get-DataGridSelectedRow.ps1")

    $script:Errors = [System.Collections.Generic.List[string]]::new()
    function Write-ContainedErrorLog { param([Parameter(ValueFromPipeline = $true)][string]$Message, $ErrorObject) process { $script:Errors.Add($Message) } }
    function Invoke-SavedQueryRequest { param($Request) }
    function Get-SqlTroubleShooterView { }
    function Update-DataGridColumnWidth { param($Grid, $Item) }
    function Get-OmadaIdentityUserName { }
    . (Join-Path $Script:QmPrivatePath "Select-QueryManagerQuery.ps1")

    function script:New-ManagerState {
        $Script:AppConfig = [PSCustomObject]@{ BaseUrl = "https://t"; IdentityUserName = "CORP\ann" }
        $Script:RunTimeData = [PSCustomObject]@{ DataobjdlgAspxAttributeMapping = [PSCustomObject]@{ SqlQueryDoId = "c-13"; SqlQueryCreatedBy = "c-2"; SqlQueryChangedBy = "c-4" } }
        $Script:QueryManagerForm = [PSCustomObject]@{
            Queries    = @()
            Ownership  = @{}
            Definition = [PSCustomObject]@{ Closed = 0 }
            Elements   = [PSCustomObject]@{
                TextBoxQueryFilter  = [PSCustomObject]@{ Text = "" }
                DataGridQueries     = [PSCustomObject]@{ ItemsSource = $null; SelectedItems = @(); SelectedCells = @(); CurrentItem = $null }
                TextBlockQueryCount = [PSCustomObject]@{ Text = "" }
                CheckBoxQueryManagerMyCreated = [PSCustomObject]@{ IsChecked = $false }
                CheckBoxQueryManagerMyUpdated = [PSCustomObject]@{ IsChecked = $false }
            }
        }
        $Script:QueryManagerForm.Definition | Add-Member -MemberType ScriptMethod -Name Close -Value { $this.Closed++ }
        $script:Errors.Clear()
    }
}

Describe 'Update-QueryManagerList' -Tag 'Unit' {
    BeforeEach {
        New-ManagerState
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $true; Result = (Get-QmFixture "odata.querylist.json") } }
        Mock Get-SqlTroubleShooterView {
            @{ "c-13" = 10521; "c-2" = "CORP\ann"; "c-4" = "CORP\bob" }
            @{ "c-13" = 10544; "c-2" = "CORP\bob"; "c-4" = "CORP\ann" }
            @{ "c-13" = 10560; "c-2" = "CORP\bob"; "c-4" = "CORP\bob" }
        }
    }

    It 'Should read who created and changed each query from the view, with the list' {
        Update-QueryManagerList -Refresh

        Should -Invoke Get-SqlTroubleShooterView -Times 1 -Exactly
        $Script:QueryManagerForm.Ownership["10521"].CreatedBy | Should -Be "CORP\ann"
        $Row = @($Script:QueryManagerForm.Elements.DataGridQueries.ItemsSource | Where-Object { $_["Id"] -eq 10544 })[0]
        $Row["CreatedBy"] | Should -Be "CORP\bob"
        $Row["ChangedBy"] | Should -Be "CORP\ann"
    }

    It 'Should show only my queries when asked: <Case>' -ForEach @(
        @{ Case = 'created'; Created = $true; Updated = $false; Expected = @(10521) }
        @{ Case = 'last updated'; Created = $false; Updated = $true; Expected = @(10544) }
        @{ Case = 'either'; Created = $true; Updated = $true; Expected = @(10521, 10544) }
    ) {
        Update-QueryManagerList -Refresh
        $Script:QueryManagerForm.Elements.CheckBoxQueryManagerMyCreated.IsChecked = $Created
        $Script:QueryManagerForm.Elements.CheckBoxQueryManagerMyUpdated.IsChecked = $Updated

        Update-QueryManagerList

        Should -Invoke Get-SqlTroubleShooterView -Times 1 -Exactly
        @($Script:QueryManagerForm.Elements.DataGridQueries.ItemsSource | ForEach-Object { $_["Id"] }) | Should -Be $Expected
        $Script:QueryManagerForm.Elements.TextBlockQueryCount.Text | Should -Be ("{0} of 6 queries" -f $Expected.Count)
    }

    It 'Should say once, in the log, that the view gave no rows, and not when it gave some' {
        Mock Write-LogOutput { }
        Update-QueryManagerList -Refresh
        Should -Invoke Write-LogOutput -Times 0 -Exactly -ParameterFilter { $LogType -eq "INFO" }

        Mock Get-SqlTroubleShooterView { }
        Update-QueryManagerList -Refresh
        Should -Invoke Write-LogOutput -Times 1 -Exactly -ParameterFilter { $LogType -eq "INFO" }
    }

    It 'Should still list the queries when the view cannot be read' {
        Mock Get-SqlTroubleShooterView { throw "no view" }

        Update-QueryManagerList -Refresh

        $Script:QueryManagerForm.Ownership.Count | Should -Be 0
        $Script:QueryManagerForm.Elements.DataGridQueries.ItemsSource.Count | Should -Be 6
    }

    It 'Should read the list from the tenant and show it all' {
        Update-QueryManagerList -Refresh

        Should -Invoke Invoke-SavedQueryRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -like "https://t/*DeletedStatus=Both*" }
        $Script:QueryManagerForm.Queries.Count | Should -Be 6
        $Script:QueryManagerForm.Elements.DataGridQueries.ItemsSource.Count | Should -Be 6
        $Script:QueryManagerForm.Elements.TextBlockQueryCount.Text | Should -Be "6 of 6 queries"
    }

    It 'Should filter the list already read without a request' {
        Update-QueryManagerList -Refresh
        $Script:QueryManagerForm.Elements.TextBoxQueryFilter.Text = "orphan"

        Update-QueryManagerList

        Should -Invoke Invoke-SavedQueryRequest -Times 1 -Exactly
        $Script:QueryManagerForm.Elements.DataGridQueries.ItemsSource.Count | Should -Be 1
        $Script:QueryManagerForm.Elements.TextBlockQueryCount.Text | Should -Be "1 of 6 queries"
    }

    It 'Should keep the list it had, and report, when the tenant cannot be read' {
        Update-QueryManagerList -Refresh
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $false; Message = "401" } }

        Update-QueryManagerList -Refresh

        $Script:QueryManagerForm.Queries.Count | Should -Be 6
        $script:Errors[0] | Should -Match "Reading the queries failed: 401"
    }
}

Describe 'ConvertFrom-QueryManagerRow' -Tag 'Unit' {
    It 'Should read the id and display name back from a row' {
        $Table = ConvertTo-QueryManagerTable -Query @([PSCustomObject]@{ Id = 42; DisplayName = "Accounts"; Name = "SQLTS_Accounts" })

        $Query = ConvertFrom-QueryManagerRow -Row $Table.Rows[0]
        $Query.DoId | Should -Be "42"
        $Query.DisplayName | Should -Be "Accounts"
    }

    It 'Should fall back to the technical name when there is no display name' {
        $Table = ConvertTo-QueryManagerTable -Query @([PSCustomObject]@{ Id = 42; DisplayName = ""; Name = "SQLTS_Accounts" })

        (ConvertFrom-QueryManagerRow -Row $Table.Rows[0]).DisplayName | Should -Be "SQLTS_Accounts"
    }
}

Describe 'Get-QueryManagerSelectedQuery' -Tag 'Unit' {
    It 'Should ask to select a query when none is' {
        New-ManagerState
        Mock Write-LogOutput { }

        Get-QueryManagerSelectedQuery | Should -BeNullOrEmpty
        Should -Invoke Write-LogOutput -Times 1 -Exactly -ParameterFilter { $LogType -eq "WARNING" }
    }

    It 'Should return the query of the selection (<Case>)' -ForEach @(
        @{ Case = 'a selected row'; Rows = @(0); Cells = @(); Current = $null }
        @{ Case = 'cells in one row'; Rows = @(); Cells = @(0, 0, 0); Current = $null }
        @{ Case = 'the row and cells in it'; Rows = @(0); Cells = @(0); Current = $null }
        @{ Case = 'only the focused cell'; Rows = @(); Cells = @(); Current = 0 }
        @{ Case = 'a selection over the focused cell'; Rows = @(); Cells = @(0); Current = 1 }
    ) {
        New-ManagerState
        Mock Write-LogOutput { }
        $Table = ConvertTo-QueryManagerTable -Query @([PSCustomObject]@{ Id = 42; DisplayName = "Accounts" }, [PSCustomObject]@{ Id = 43; DisplayName = "Groups" })
        $View = $Table.DefaultView
        $Grid = $Script:QueryManagerForm.Elements.DataGridQueries
        $Grid.SelectedItems = @($Rows | ForEach-Object { $View[$_] })
        $Grid.SelectedCells = @($Cells | ForEach-Object { [PSCustomObject]@{ Item = $View[$_] } })
        $Grid.CurrentItem = if ($null -ne $Current) { $View[$Current] } else { $null }

        $Query = Get-QueryManagerSelectedQuery

        $Query.DoId | Should -Be "42"
        $Query.DisplayName | Should -Be "Accounts"
        Should -Invoke Write-LogOutput -Times 0 -Exactly
    }

    It 'Should refuse a selection over more than one query (<Case>)' -ForEach @(
        @{ Case = 'two rows'; Rows = @(0, 1); Cells = @() }
        @{ Case = 'cells in two rows'; Rows = @(); Cells = @(0, 1) }
        @{ Case = 'a row and a cell in another'; Rows = @(0); Cells = @(1) }
    ) {
        New-ManagerState
        Mock Write-LogOutput { }
        $Table = ConvertTo-QueryManagerTable -Query @([PSCustomObject]@{ Id = 42; DisplayName = "Accounts" }, [PSCustomObject]@{ Id = 43; DisplayName = "Groups" })
        $View = $Table.DefaultView
        $Grid = $Script:QueryManagerForm.Elements.DataGridQueries
        $Grid.SelectedItems = @($Rows | ForEach-Object { $View[$_] })
        $Grid.SelectedCells = @($Cells | ForEach-Object { [PSCustomObject]@{ Item = $View[$_] } })

        Get-QueryManagerSelectedQuery | Should -BeNullOrEmpty
        Should -Invoke Write-LogOutput -Times 1 -Exactly -ParameterFilter { $LogType -eq "WARNING" -and $Message -match "^2 queries are selected" }
    }
}

Describe 'Request-QueryManagerClose and Complete-QueryManagerChildWindow' -Tag 'Unit' {
    BeforeEach {
        New-ManagerState
        $Script:QueryManagerCloseRequested = $false
    }

    It 'Should leave a window open when no close was requested' {
        Complete-QueryManagerChildWindow -Window $Script:QueryManagerForm.Definition | Should -BeFalse
        $Script:QueryManagerForm.Definition.Closed | Should -Be 0
    }

    It 'Should close the window once a close was requested' {
        Request-QueryManagerClose

        Complete-QueryManagerChildWindow -Window $Script:QueryManagerForm.Definition | Should -BeTrue
        $Script:QueryManagerForm.Definition.Closed | Should -Be 1
    }
}

Describe 'Query manager views, user name and buttons' -Tag 'Unit' {
    BeforeEach {
        New-ManagerState
        $script:Selected = $null
        $Script:QueryManagerForm.Elements | Add-Member -NotePropertyName ComboBoxQueryManagerView -NotePropertyValue ([PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Tag = "Active" } }) -Force
        foreach ($Name in @("ButtonOpenQueryObject", "ButtonOpenQueryObjectInTab", "ButtonShowQueryObjectDetails", "ButtonRenameQueryObject", "ButtonDeleteQueryObject", "ButtonRestoreQueryObject", "ButtonOpenQueryObjectInOmada", "ButtonOpenQueryObjectOData")) {
            $Script:QueryManagerForm.Elements | Add-Member -NotePropertyName $Name -NotePropertyValue ([PSCustomObject]@{ IsEnabled = $null }) -Force
        }
        $Lists = @(
            [PSCustomObject]@{ Id = 1; DisplayName = "Live"; Name = "Live"; Deleted = $false }
            [PSCustomObject]@{ Id = 2; DisplayName = "Gone"; Name = "Gone"; Deleted = $true }
            [PSCustomObject]@{ Id = 3; DisplayName = "TMP"; Name = "TMP_0a1b"; Deleted = $true }
        )
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $true; Result = [PSCustomObject]@{ value = $Lists } } }
        Mock Get-SqlTroubleShooterView { }
    }

    It 'Should show the queries of the view: <View>' -ForEach @(
        @{ View = "Active"; Expected = @(1) }
        @{ View = "Deleted"; Expected = @(2) }
        @{ View = "All"; Expected = @(1, 2) }
    ) {
        $Script:QueryManagerForm.Elements.ComboBoxQueryManagerView.SelectedItem.Tag = $View

        Update-QueryManagerList -Refresh

        @($Script:QueryManagerForm.Elements.DataGridQueries.ItemsSource | ForEach-Object { $_["Id"] }) | Should -Be $Expected
        $Script:QueryManagerForm.Elements.TextBlockQueryCount.Text | Should -Be ("{0} of {0} queries" -f $Expected.Count)
    }

    It 'Should show the not deleted queries for a view it does not know' {
        $Script:QueryManagerForm.Elements.ComboBoxQueryManagerView.SelectedItem.Tag = "Other"
        Get-QueryManagerView | Should -Be "Active"
    }

    It 'Should grey out every button that needs a query while none is selected' {
        Update-QueryManagerList -Refresh

        foreach ($Name in @("ButtonOpenQueryObject", "ButtonShowQueryObjectDetails", "ButtonDeleteQueryObject", "ButtonRestoreQueryObject", "ButtonOpenQueryObjectOData")) {
            $Script:QueryManagerForm.Elements.$Name.IsEnabled | Should -BeFalse
        }
    }

    It 'Should enable the buttons for the selected query, and Restore only for a deleted one' {
        $Script:QueryManagerForm.Elements.ComboBoxQueryManagerView.SelectedItem.Tag = "All"
        Update-QueryManagerList -Refresh
        $View = $Script:QueryManagerForm.Elements.DataGridQueries.ItemsSource
        $Grid = $Script:QueryManagerForm.Elements.DataGridQueries

        $Grid.SelectedItems = @($View[1])
        Update-QueryManagerCommandState
        $Script:QueryManagerForm.Elements.ButtonRestoreQueryObject.IsEnabled | Should -BeTrue
        $Script:QueryManagerForm.Elements.ButtonDeleteQueryObject.IsEnabled | Should -BeFalse
        $Script:QueryManagerForm.Elements.ButtonShowQueryObjectDetails.IsEnabled | Should -BeTrue

        $Grid.SelectedItems = @($View[0])
        Update-QueryManagerCommandState
        $Script:QueryManagerForm.Elements.ButtonRestoreQueryObject.IsEnabled | Should -BeFalse
        $Script:QueryManagerForm.Elements.ButtonDeleteQueryObject.IsEnabled | Should -BeTrue
        $Script:QueryManagerForm.Elements.ButtonOpenQueryObjectInTab.IsEnabled | Should -BeTrue
    }

    It 'Should read the user name for its filters itself when the tab has none, once' {
        $Script:AppConfig.IdentityUserName = $null
        Mock Get-OmadaIdentityUserName { "CORP\ann" }

        Get-QueryManagerUserName -Needed $true | Should -Be "CORP\ann"
        Get-QueryManagerUserName -Needed $true | Should -Be "CORP\ann"

        Should -Invoke Get-OmadaIdentityUserName -Times 1 -Exactly
    }

    It 'Should use the tab''s user name when it has one' {
        Mock Get-OmadaIdentityUserName { "other" }

        Get-QueryManagerUserName -Needed $true | Should -Be "CORP\ann"
        Should -Invoke Get-OmadaIdentityUserName -Times 0 -Exactly
    }

    It 'Should not ask for the user name while no filter is on' {
        Mock Get-OmadaIdentityUserName { "x" }

        Get-QueryManagerUserName -Needed $false | Should -Be ""
        Should -Invoke Get-OmadaIdentityUserName -Times 0 -Exactly
    }

    It 'Should warn once, and ask no more, when the user name cannot be read' {
        $Script:AppConfig.IdentityUserName = $null
        Mock Get-OmadaIdentityUserName { throw "no page" }
        Mock Write-LogOutput { }

        Get-QueryManagerUserName -Needed $true | Should -Be ""
        Get-QueryManagerUserName -Needed $true | Should -Be ""

        Should -Invoke Get-OmadaIdentityUserName -Times 1 -Exactly
        Should -Invoke Write-LogOutput -Times 1 -Exactly -ParameterFilter { $LogType -eq "WARNING" }
    }

    It 'Should filter on my queries when the main window''s filters are off (no user name on the tab)' {
        $Script:AppConfig.IdentityUserName = $null
        Mock Get-OmadaIdentityUserName { "CORP\ann" }
        Mock Get-SqlTroubleShooterView { @{ "c-13" = 1; "c-2" = "CORP\bob"; "c-4" = "CORP\bob" }; @{ "c-13" = 2; "c-2" = "CORP\ann"; "c-4" = "CORP\ann" } }
        $Script:QueryManagerForm.Elements.ComboBoxQueryManagerView.SelectedItem.Tag = "All"
        $Script:QueryManagerForm.Elements.CheckBoxQueryManagerMyCreated.IsChecked = $true

        Update-QueryManagerList -Refresh

        @($Script:QueryManagerForm.Elements.DataGridQueries.ItemsSource | ForEach-Object { $_["Id"] }) | Should -Be @(2)
    }
}

Describe 'Get-QueryManagerCommandState' -Tag 'Unit' {
    It 'Should allow <Case>' -ForEach @(
        @{ Case = 'nothing without a query'; Query = $null; Enabled = @() }
        @{ Case = 'everything but Restore for a query'; Query = [PSCustomObject]@{ Deleted = $false }; Enabled = @("Delete", "Details", "OData", "Omada", "Open", "OpenInTab", "Rename") }
        @{ Case = 'only Details and Restore for a deleted query'; Query = [PSCustomObject]@{ Deleted = $true }; Enabled = @("Details", "Restore") }
    ) {
        $State = Get-QueryManagerCommandState -Query $Query
        @($State.Keys | Where-Object { $State[$_] } | Sort-Object) | Should -Be $Enabled
        $State.Keys.Count | Should -Be 8
    }
}

Describe 'Get-QueryManagerSelectedQuery -Quiet' -Tag 'Unit' {
    It 'Should give the one selected query, deleted or not, and nothing otherwise, without a word' {
        New-ManagerState
        Mock Write-LogOutput { }
        $Table = ConvertTo-QueryManagerTable -Query @([PSCustomObject]@{ Id = 1; DisplayName = "A"; Deleted = $true }, [PSCustomObject]@{ Id = 2; DisplayName = "B"; Deleted = $false })
        $Grid = $Script:QueryManagerForm.Elements.DataGridQueries

        $Grid.SelectedItems = @($Table.DefaultView[0])
        (Get-QueryManagerSelectedQuery -Quiet).Deleted | Should -BeTrue
        $Grid.SelectedItems = @($Table.DefaultView[1])
        (Get-QueryManagerSelectedQuery -Quiet).Deleted | Should -BeFalse
        $Grid.SelectedItems = @($Table.DefaultView[0], $Table.DefaultView[1])
        Get-QueryManagerSelectedQuery -Quiet | Should -BeNullOrEmpty
        $Grid.SelectedItems = @()
        Get-QueryManagerSelectedQuery -Quiet | Should -BeNullOrEmpty

        Should -Invoke Write-LogOutput -Times 0 -Exactly -ParameterFilter { $LogType -eq "WARNING" }
    }
}
