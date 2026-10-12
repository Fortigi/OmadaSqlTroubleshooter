#Requires -Version 7.0
# Issue #165: fill the schema tree's database nodes from the cache, so the search covers them.
#
# The preload caches every database's schema shortly after connect. The schema window is usually
# opened later, and builds those databases as empty nodes with a "Loading..." placeholder - so a search
# never found a table in a folded database, although its schema was in hand. This function fills them,
# and the filter calls it before the first search.
#
# The tree items are plain objects (New-SqlSchemaTreeItem stubbed, as in SqlSchemaDatabaseTree.Tests.ps1)
# so no WPF or STA runspace is needed. Add-SqlSchemaTreeNode is the REAL builder: what a filled node
# looks like is its decision, and a stub would let the two drift.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Add-SqlSchemaTreeNode.ps1")
    . (Join-Path $PrivatePath -ChildPath "Add-SqlSchemaCachedDatabaseNode.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    $script:LogMessages = [System.Collections.Generic.List[object]]::new()
    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
        process { $script:LogMessages.Add([pscustomobject]@{ LogType = $LogType; Message = [string]$InputObject }) }
    }

    function Write-ContainedErrorLog {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, $ErrorObject)
        process { $script:ContainedErrors++ }
    }

    # The real key format is "<SessionKey>|<DoId>"; only that it is per DoId matters here.
    function Get-SqlSchemaCacheKey {
        param([string]$DataConnectionDoId)
        return "session-a|{0}" -f $DataConnectionDoId
    }

    # Must never be reached: this function answers from the cache only.
    function Get-SqlSchemaObject { $script:FetchCalls++ }

    # Defined AFTER Add-SqlSchemaTreeNode.ps1 is dot-sourced, so it replaces the WPF factory in it.
    function New-SqlSchemaTreeItem {
        param([string]$Header, [int]$FontSize = 14, [switch]$IsExpanded, $Tag)

        return [PSCustomObject]@{
            Header     = $Header
            IsExpanded = $IsExpanded.IsPresent
            Tag        = $Tag
            Items      = [System.Collections.Generic.List[object]]::new()
        }
    }

    function script:New-DatabaseNode {
        param([string]$DoId, [string]$Name, [bool]$Loaded = $false)

        $Private:Node = New-SqlSchemaTreeItem -Header $Name -Tag ([PSCustomObject]@{
                DoId      = $DoId
                Name      = $Name
                Loaded    = $Loaded
                Requested = $false
            })
        $Private:Node.Items.Add((New-SqlSchemaTreeItem -Header "Loading..." -FontSize 12))

        return $Private:Node
    }

    # The shape GetSqlSchema answers with: one "schema.table" property per table, its columns as strings.
    function script:New-SchemaResponse {
        param([hashtable]$Table)

        $Private:Payload = [PSCustomObject]@{}
        foreach ($Private:Key in $Table.Keys) {
            $Private:Payload | Add-Member -NotePropertyName $Private:Key -NotePropertyValue $Table[$Private:Key]
        }

        return [PSCustomObject]@{ d = $Private:Payload }
    }

    function script:Get-TableHeader {
        param($Node)
        return @($Node.Items | ForEach-Object { $_.Items } | ForEach-Object { $_.Header })
    }
}

Describe "Add-SqlSchemaCachedDatabaseNode" {

    BeforeEach {
        $script:FetchCalls = 0
        $script:ContainedErrors = 0
        $script:LogMessages.Clear()

        $script:Esarc = New-DatabaseNode -DoId "1001574" -Name "ESARC"
        $script:Rope = New-DatabaseNode -DoId "1001261" -Name "RoPE"
        $Script:TreeViewSqlSchema = [PSCustomObject]@{ Items = @($script:Esarc, $script:Rope) }

        # ESARC's schema was preloaded; RoPE's was not.
        $Script:SqlSchemaCache = @{
            "session-a|1001574" = (New-SchemaResponse -Table @{
                    "dbo.tblCalculatedAssignment" = @("Id int", "Name nvarchar")
                    "dbo.tblExport"               = @("Id int")
                })
        }
    }

    It "fills a database whose schema is cached" {
        Add-SqlSchemaCachedDatabaseNode | Should -Be 1

        Get-TableHeader -Node $script:Esarc | Sort-Object | Should -Be @("tblCalculatedAssignment", "tblExport")
    }

    It "replaces the placeholder" {
        Add-SqlSchemaCachedDatabaseNode | Out-Null

        @($script:Esarc.Items | Where-Object { $_.Header -eq "Loading..." }).Count | Should -Be 0
    }

    It "marks it loaded and requested, so expanding it fetches nothing" {
        Add-SqlSchemaCachedDatabaseNode | Out-Null

        $script:Esarc.Tag.Loaded | Should -BeTrue
        $script:Esarc.Tag.Requested | Should -BeTrue
    }

    It "leaves a database whose schema is not cached as it is" {
        Add-SqlSchemaCachedDatabaseNode | Out-Null

        $script:Rope.Tag.Loaded | Should -BeFalse
        @($script:Rope.Items).Header | Should -Be @("Loading...")
    }

    It "does not rebuild a database that is already loaded" {
        # A second search must cost a walk of the database level, not a rebuild.
        Add-SqlSchemaCachedDatabaseNode | Out-Null
        $Private:FirstSchemaNode = $script:Esarc.Items[0]

        Add-SqlSchemaCachedDatabaseNode | Should -Be 0

        [object]::ReferenceEquals($script:Esarc.Items[0], $Private:FirstSchemaNode) | Should -BeTrue
    }

    It "makes no request" {
        Add-SqlSchemaCachedDatabaseNode | Out-Null

        $script:FetchCalls | Should -Be 0
    }

    It "says how many databases it filled" {
        Add-SqlSchemaCachedDatabaseNode | Out-Null

        @($script:LogMessages | Where-Object { $_.Message -like "Filled 1 database(s)*" }).Count | Should -Be 1
    }

    It "does nothing when the schema window was never opened" {
        $Script:TreeViewSqlSchema = $null

        Add-SqlSchemaCachedDatabaseNode | Should -Be 0
    }

    It "does nothing when nothing is cached" {
        $Script:SqlSchemaCache = @{}

        Add-SqlSchemaCachedDatabaseNode | Should -Be 0
        $script:Esarc.Tag.Loaded | Should -BeFalse
    }

    It "skips a node without a Tag rather than failing" {
        $Script:TreeViewSqlSchema = [PSCustomObject]@{ Items = @((New-SqlSchemaTreeItem -Header "stray"), $script:Esarc) }

        Add-SqlSchemaCachedDatabaseNode | Should -Be 1
        $script:ContainedErrors | Should -Be 0
    }
}
