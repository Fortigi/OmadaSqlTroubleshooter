#Requires -Version 7.0
# The schema tree's builder: schema -> table, with each table's columns deferred until it is expanded.
#
# Building every column node up front made a 565-table database 9,060 tree items and 4.5 s on the UI
# thread; deferring them makes it 1,150 and a third of a second. What is asserted here is that nothing
# is lost by it: the same schemas and tables, the same raw column headers once a table is opened, and
# no request for any of it.
#
# New-SqlSchemaTreeItem is stubbed with a plain object (as in SqlSchemaDatabaseTree.Tests.ps1), so no
# WPF and no STA runspace is needed.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Add-SqlSchemaTreeNode.ps1")
    . (Join-Path $PrivatePath -ChildPath "Update-SqlSchemaDatabaseTree.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
        process { }
    }

    function Write-ContainedErrorLog {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, $ErrorObject)
        process { $script:ContainedErrors++ }
    }

    # Must never be reached by a table expanding: its columns are already in hand.
    function Get-SqlSchemaObject { $script:FetchCalls++ }

    # Defined AFTER Add-SqlSchemaTreeNode.ps1 is dot-sourced, so it replaces the WPF factory in it.
    function New-SqlSchemaTreeItem {
        param([string]$Header, [int]$FontSize = 14, [switch]$IsExpanded, $Tag)

        return [PSCustomObject]@{
            Header     = $Header
            FontSize   = $FontSize
            IsExpanded = $IsExpanded.IsPresent
            Tag        = if ($PSBoundParameters.ContainsKey("Tag")) { $Tag } else { $null }
            Items      = [System.Collections.Generic.List[object]]::new()
        }
    }

    function script:New-SchemaResponse {
        param([System.Collections.Specialized.OrderedDictionary]$Table)

        $Private:Payload = [PSCustomObject]@{}
        foreach ($Private:Key in $Table.Keys) {
            $Private:Payload | Add-Member -NotePropertyName $Private:Key -NotePropertyValue $Table[$Private:Key]
        }

        return [PSCustomObject]@{ d = $Private:Payload }
    }

    function script:Get-TableNode {
        param($Parent, [string]$Schema, [string]$Table)
        $Private:SchemaNode = $Parent.Items | Where-Object { $_.Header -eq $Schema }
        return $Private:SchemaNode.Items | Where-Object { $_.Header -eq $Table }
    }
}

Describe "Add-SqlSchemaTreeNode - schemas and tables" {

    BeforeEach {
        $script:Parent = New-SqlSchemaTreeItem -Header "ODW"
    }

    It "groups tables under their schema, whatever order they arrive in" {
        Add-SqlSchemaTreeNode -Parent $script:Parent -SchemaResponse (New-SchemaResponse -Table ([ordered]@{
                    "dbo.tblA"   = @("Id int")
                    "stage.tblB" = @("Id int")
                    "dbo.tblC"   = @("Id int")
                })) | Should -Be 3

        @($script:Parent.Items.Header) | Should -Be @("dbo", "stage")
        @(($script:Parent.Items | Where-Object { $_.Header -eq "dbo" }).Items.Header) | Should -Be @("tblA", "tblC")
        @(($script:Parent.Items | Where-Object { $_.Header -eq "stage" }).Items.Header) | Should -Be @("tblB")
    }

    It "splits a table name on the first dot only" {
        Add-SqlSchemaTreeNode -Parent $script:Parent -SchemaResponse (New-SchemaResponse -Table ([ordered]@{ "dbo.tbl.With.Dots" = @("Id int") })) | Out-Null

        @($script:Parent.Items[0].Items.Header) | Should -Be @("tbl.With.Dots")
    }

    It "builds no column nodes yet - a placeholder gives the table its expander arrow" {
        Add-SqlSchemaTreeNode -Parent $script:Parent -SchemaResponse (New-SchemaResponse -Table ([ordered]@{ "dbo.tblA" = @("Id int", "Name nvarchar(50)") })) | Out-Null

        $Private:Table = Get-TableNode -Parent $script:Parent -Schema "dbo" -Table "tblA"
        @($Private:Table.Items.Header) | Should -Be @("Loading...")
        $Private:Table.Tag.ColumnsBuilt | Should -BeFalse
    }

    It "still counts a table with no columns" {
        Add-SqlSchemaTreeNode -Parent $script:Parent -SchemaResponse (New-SchemaResponse -Table ([ordered]@{ "dbo.tblEmpty" = @() })) | Should -Be 1
    }
}

Describe "Add-SqlSchemaTreeColumnNode - columns on first expand" {

    BeforeEach {
        $script:Parent = New-SqlSchemaTreeItem -Header "ODW"
        Add-SqlSchemaTreeNode -Parent $script:Parent -SchemaResponse (New-SchemaResponse -Table ([ordered]@{
                    "dbo.tblA" = @("Id int", "DisplayName nvarchar(50) NOT NULL")
                })) | Out-Null
        $script:Table = Get-TableNode -Parent $script:Parent -Schema "dbo" -Table "tblA"
    }

    It "builds the columns with their raw headers, which shift-click splits back apart" {
        Add-SqlSchemaTreeColumnNode -TableItem $script:Table | Should -BeTrue

        @($script:Table.Items.Header) | Should -Be @("Id int", "DisplayName nvarchar(50) NOT NULL")
        @($script:Table.Items.FontSize) | Should -Be @(12, 12)
    }

    It "does nothing the second time" {
        Add-SqlSchemaTreeColumnNode -TableItem $script:Table | Out-Null
        $Private:First = $script:Table.Items[0]

        Add-SqlSchemaTreeColumnNode -TableItem $script:Table | Should -BeFalse

        [object]::ReferenceEquals($script:Table.Items[0], $Private:First) | Should -BeTrue
    }

    It "ignores a node that is not a table" {
        Add-SqlSchemaTreeColumnNode -TableItem $script:Parent.Items[0] | Should -BeFalse
        Add-SqlSchemaTreeColumnNode -TableItem $null | Should -BeFalse
    }
}

Describe "Invoke-SqlSchemaDatabaseNodeExpanded - a table expanding inside its database" {
    # Expanded bubbles, so the database node's handler sees a table opening. That is the trigger for
    # the columns: one handler per database, none per table.

    BeforeEach {
        $script:FetchCalls = 0
        $script:ContainedErrors = 0

        $script:Database = New-SqlSchemaTreeItem -Header "ODW" -Tag ([PSCustomObject]@{ DoId = "1001262"; Name = "ODW"; Loaded = $true; Requested = $true })
        Add-SqlSchemaTreeNode -Parent $script:Database -SchemaResponse (New-SchemaResponse -Table ([ordered]@{ "dbo.tblA" = @("Id int") })) | Out-Null
        $script:Table = Get-TableNode -Parent $script:Database -Schema "dbo" -Table "tblA"
    }

    It "builds the columns of the table that was expanded" {
        $Private:ExpandedArgs = [PSCustomObject]@{ OriginalSource = $script:Table; Handled = $false }

        Invoke-SqlSchemaDatabaseNodeExpanded -Sender $script:Database -EventArgs $Private:ExpandedArgs

        @($script:Table.Items.Header) | Should -Be @("Id int")
        $Private:ExpandedArgs.Handled | Should -BeTrue
    }

    It "makes no request for it" {
        Invoke-SqlSchemaDatabaseNodeExpanded -Sender $script:Database -EventArgs ([PSCustomObject]@{ OriginalSource = $script:Table; Handled = $false })

        $script:FetchCalls | Should -Be 0
        $script:ContainedErrors | Should -Be 0
    }

    It "still fetches an unloaded database expanded by itself" {
        $script:Database.Tag.Loaded = $false
        $script:Database.Tag.Requested = $false

        Invoke-SqlSchemaDatabaseNodeExpanded -Sender $script:Database -EventArgs ([PSCustomObject]@{ OriginalSource = $script:Database; Handled = $false })

        $script:FetchCalls | Should -Be 1
    }

    It "does not fetch when a schema node inside a loaded database is expanded" {
        Invoke-SqlSchemaDatabaseNodeExpanded -Sender $script:Database -EventArgs ([PSCustomObject]@{ OriginalSource = $script:Database.Items[0]; Handled = $false })

        $script:FetchCalls | Should -Be 0
    }
}
