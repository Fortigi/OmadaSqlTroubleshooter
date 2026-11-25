#Requires -Version 7.0
BeforeAll {
    # WPF's new-item placeholder is an MS.Internal.NamedObject; a type of the same name stands in for
    # it, since PresentationFramework is not loaded in the headless lane.
    if (-not ("OmadaSqlTroubleshooterTests.NamedObject" -as [type])) {
        Add-Type -TypeDefinition "namespace OmadaSqlTroubleshooterTests { public class NamedObject { } }"
    }

    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Get-DataGridSelectedRow.ps1")

    function New-TestGrid {
        param($Rows = @(), $Cells = @(), $Current = $null)
        [PSCustomObject]@{ SelectedItems = @($Rows); SelectedCells = @($Cells | ForEach-Object { [PSCustomObject]@{ Item = $_ } }); CurrentItem = $Current }
    }
}

Describe 'Get-DataGridSelectedRow' -Tag 'Unit' {
    BeforeAll {
        $A = [PSCustomObject]@{ Name = "a" }
        $B = [PSCustomObject]@{ Name = "b" }
    }

    It 'Should give the rows of <Case>' -ForEach @(
        @{ Case = 'selected rows'; Rows = 'A', 'B'; Cells = @(); Current = $null; Expected = 'a', 'b' }
        @{ Case = 'selected cells'; Rows = @(); Cells = 'B', 'B', 'A'; Current = $null; Expected = 'b', 'a' }
        @{ Case = 'a row and cells in it'; Rows = 'A'; Cells = 'A', 'A'; Current = $null; Expected = @('a') }
        @{ Case = 'the focused cell, with nothing selected'; Rows = @(); Cells = @(); Current = 'B'; Expected = @('b') }
        @{ Case = 'the selection, not the focused cell'; Rows = @(); Cells = 'A'; Current = 'B'; Expected = @('a') }
    ) {
        $Map = @{ A = $A; B = $B }
        $Grid = New-TestGrid -Rows @($Rows | ForEach-Object { $Map[$_] }) -Cells @($Cells | ForEach-Object { $Map[$_] }) -Current $(if ($Current) { $Map[$Current] })

        @(Get-DataGridSelectedRow -Grid $Grid).Name | Should -Be $Expected
    }

    It 'Should give nothing without a grid or a selection' {
        @(Get-DataGridSelectedRow -Grid $null).Count | Should -Be 0
        @(Get-DataGridSelectedRow -Grid (New-TestGrid)).Count | Should -Be 0
    }
}

Describe 'Get-DataGridSelectionRow' -Tag 'Unit' {
    It 'Should keep each row once, by reference, in first-seen order' {
        $A = [PSCustomObject]@{ Row = "same" }
        $B = [PSCustomObject]@{ Row = "same" }
        $Rows = @(Get-DataGridSelectionRow -Item @($A, $null, $B, $A, $B))

        $Rows.Count | Should -Be 2
        [object]::ReferenceEquals($Rows[0], $A) | Should -BeTrue
        [object]::ReferenceEquals($Rows[1], $B) | Should -BeTrue
    }

    It 'Should leave out the grid''s new-item placeholder' {
        $Placeholder = [OmadaSqlTroubleshooterTests.NamedObject]::new()
        @(Get-DataGridSelectionRow -Item @($Placeholder)).Count | Should -Be 0
    }

    It 'Should give nothing for nothing' {
        @(Get-DataGridSelectionRow -Item @()).Count | Should -Be 0
        @(Get-DataGridSelectionRow -Item $null).Count | Should -Be 0
    }
}
