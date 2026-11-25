#Requires -Version 7.0
BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Update-SqlHistorySelection.ps1")
    . (Join-Path $PrivatePath "Get-DataGridSelectedRow.ps1")

    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)]$Message, $LogType) process { } }
    function Format-OmadaHistoryDate { param($Value) if ($null -eq $Value) { "(unknown)" } else { $Value.ToString("yyyy-MM-dd HH:mm:ss") } }
    function Invoke-GenerateDiffView { param($OldValue, $NewValue) }

    function script:New-Blocks {
        $Blocks = [PSCustomObject]@{ Cleared = 0 }
        $Blocks | Add-Member -MemberType ScriptMethod -Name Clear -Value { $this.Cleared++ }
        [PSCustomObject]@{ Blocks = $Blocks }
    }
    function script:New-HistoryState {
        param($Rows = @(), $Cells = @())
        $Script:SqlHistoryForm = [PSCustomObject]@{
            Elements = @{
                DataGridHistory        = [PSCustomObject]@{ SelectedItems = @($Rows); SelectedCells = @($Cells | ForEach-Object { [PSCustomObject]@{ Item = $_ } }); CurrentItem = $null }
                DataGridHistoryDetails = [PSCustomObject]@{ ItemsSource = $null }
                ButtonRestoreQuery     = [PSCustomObject]@{ IsEnabled = $null }
                TextBoxOldValue        = [PSCustomObject]@{ Text = "previous" }
                TextBoxNewValue        = [PSCustomObject]@{ Text = "previous" }
                RichTextBoxOldDiff     = [PSCustomObject]@{ Document = (New-Blocks) }
                RichTextBoxNewDiff     = [PSCustomObject]@{ Document = (New-Blocks) }
            }
        }
    }
    $script:V1 = [PSCustomObject]@{ DoId = "42"; SqlObjectName = "Accounts"; ChangedBy = "Ann"; ChangeDate = [datetime]"2026-11-01 10:00:00"; OldValue = "SELECT 1"; NewValue = "SELECT 2" }
    $script:V2 = [PSCustomObject]@{ DoId = "42"; SqlObjectName = "Accounts"; ChangedBy = "Bob"; ChangeDate = $null; OldValue = "SELECT 2"; NewValue = "SELECT 3" }
}

Describe 'Update-SqlHistorySelection' -Tag 'Unit' {
    BeforeEach {
        Mock Invoke-GenerateDiffView { }
    }

    It 'Should show the version of <Case>, and enable Restore' -ForEach @(
        @{ Case = 'a selected row'; Rows = @('V1'); Cells = @() }
        @{ Case = 'cells in one row'; Rows = @(); Cells = @('V1', 'V1') }
    ) {
        New-HistoryState -Rows @($Rows | ForEach-Object { Get-Variable -Name $_ -Scope Script -ValueOnly }) -Cells @($Cells | ForEach-Object { Get-Variable -Name $_ -Scope Script -ValueOnly })

        Update-SqlHistorySelection

        $Elements = $Script:SqlHistoryForm.Elements
        $Elements.TextBoxOldValue.Text | Should -Be "SELECT 1"
        $Elements.TextBoxNewValue.Text | Should -Be "SELECT 2"
        $Elements.ButtonRestoreQuery.IsEnabled | Should -BeTrue
        @($Elements.DataGridHistoryDetails.ItemsSource).Count | Should -Be 4
        Should -Invoke Invoke-GenerateDiffView -Times 1 -Exactly -ParameterFilter { $OldValue -eq "SELECT 1" -and $NewValue -eq "SELECT 2" }
    }

    It 'Should clear the panes and disable Restore for <Case>' -ForEach @(
        @{ Case = 'no selection'; Rows = @(); Cells = @() }
        @{ Case = 'two versions'; Rows = @('V1'); Cells = @('V2') }
    ) {
        New-HistoryState -Rows @($Rows | ForEach-Object { Get-Variable -Name $_ -Scope Script -ValueOnly }) -Cells @($Cells | ForEach-Object { Get-Variable -Name $_ -Scope Script -ValueOnly })

        Update-SqlHistorySelection

        $Elements = $Script:SqlHistoryForm.Elements
        $Elements.TextBoxOldValue.Text | Should -Be ""
        $Elements.TextBoxNewValue.Text | Should -Be ""
        $Elements.ButtonRestoreQuery.IsEnabled | Should -BeFalse
        @($Elements.DataGridHistoryDetails.ItemsSource).Count | Should -Be 0
        $Elements.RichTextBoxOldDiff.Document.Blocks.Cleared | Should -Be 1
        $Elements.RichTextBoxNewDiff.Document.Blocks.Cleared | Should -Be 1
        Should -Invoke Invoke-GenerateDiffView -Times 0 -Exactly
    }
}

Describe 'ConvertTo-HistoryDetailList' -Tag 'Unit' {
    It 'Should list the version''s fields as Property / Value rows' {
        $Rows = @(ConvertTo-HistoryDetailList -Item $script:V1)

        $Rows.Property | Should -Be @("Query DoId", "Query name", "Changed by", "Change date")
        $Rows.Value | Should -Be @("42", "Accounts", "Ann", "2026-11-01 10:00:00")
    }

    It 'Should render an unreadable change date rather than fail on it' {
        (@(ConvertTo-HistoryDetailList -Item $script:V2) | Where-Object Property -eq "Change date").Value | Should -Be "(unknown)"
    }

    It 'Should give no rows for no version' {
        @(ConvertTo-HistoryDetailList -Item $null).Count | Should -Be 0
    }
}
