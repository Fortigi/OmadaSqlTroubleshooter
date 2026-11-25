#Requires -Version 7.0
# The window itself needs WPF; what it does with its data does not.

BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManager.Shared.ps1")
    . (Join-Path $Script:QmPrivatePath "Open-QueryManagerForm.ps1")

    $script:Errors = [System.Collections.Generic.List[string]]::new()
    function Write-ContainedErrorLog { param([Parameter(ValueFromPipeline = $true)][string]$Message, $ErrorObject) process { $script:Errors.Add($Message) } }
    function Invoke-SavedQueryRequest { param($Request) }

    function script:New-ManagerState {
        $Script:AppConfig = [PSCustomObject]@{ BaseUrl = "https://t" }
        $Script:QueryManagerForm = [PSCustomObject]@{
            Queries    = @()
            Definition = [PSCustomObject]@{ Closed = 0 }
            Elements   = [PSCustomObject]@{
                TextBoxQueryFilter  = [PSCustomObject]@{ Text = "" }
                DataGridQueries     = [PSCustomObject]@{ ItemsSource = $null; SelectedItems = @(); SelectedCells = @(); CurrentItem = $null }
                TextBlockQueryCount = [PSCustomObject]@{ Text = "" }
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
    }

    It 'Should read the list from the tenant and show it all' {
        Update-QueryManagerList -Refresh

        Should -Invoke Invoke-SavedQueryRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -like "https://t/*Deleted ne true*" }
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

Describe 'Get-QueryManagerSelectionRow' -Tag 'Unit' {
    It 'Should keep each row once, by reference, in first-seen order, and drop what is not a row' {
        $A = [PSCustomObject]@{ Row = "a" }
        $B = [PSCustomObject]@{ Row = "a" }
        $Rows = @(Get-QueryManagerSelectionRow -Item @($A, $null, $B, $A, [PSCustomObject]@{ Other = 1 }, "text", $B))

        $Rows.Count | Should -Be 2
        [object]::ReferenceEquals($Rows[0], $A) | Should -BeTrue
        [object]::ReferenceEquals($Rows[1], $B) | Should -BeTrue
    }

    It 'Should give nothing for nothing' {
        @(Get-QueryManagerSelectionRow -Item @()).Count | Should -Be 0
        @(Get-QueryManagerSelectionRow -Item $null).Count | Should -Be 0
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
