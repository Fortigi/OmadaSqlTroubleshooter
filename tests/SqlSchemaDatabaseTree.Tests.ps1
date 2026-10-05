#Requires -Version 7.0
# Issue #158 criterion 1: the schema window lists every data connection as a collapsible node and
# loads each one's schema on first expand.
#
# The tree is built out of New-SqlSchemaTreeItem, which is stubbed here with a plain object. That is
# what lets this file assert the thing the issue actually changed - WHICH LEVEL CARRIES WHAT, and
# when a fetch happens - without WPF and without an STA runspace.
#
# Criterion 3 ("opening the schema window costs no more round trips than today") is a statement about
# fetches, so the fetch is the seam that is counted.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Resolve-DataConnectionReference.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-ContainedErrorLog.ps1")
    . (Join-Path $PrivatePath -ChildPath "Add-SqlSchemaTreeNode.ps1")
    . (Join-Path $PrivatePath -ChildPath "Update-SqlSchemaDatabaseTree.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog,
            [switch]$TabScoped
        )
        process { }
    }

    function Get-DataConnectionOptionText {
        param([switch]$NoRefresh)
        return , @("OISES - 1001572", "Reporting - 1001999")
    }

    # Stands in for the WPF factory. Items is a real list so Add/Clear/Remove behave, and
    # Add_Expanded records the handler so a test can raise the event the way WPF would.
    function New-SqlSchemaTreeItem {
        param(
            [string]$Header,
            [int]$FontSize = 14,
            [switch]$IsExpanded,
            $Tag
        )

        $Item = [PSCustomObject]@{
            Header     = $Header
            FontSize   = $FontSize
            IsExpanded = $IsExpanded.IsPresent
            Tag        = if ($PSBoundParameters.ContainsKey("Tag")) { $Tag } else { $null }
            Items      = [System.Collections.Generic.List[object]]::new()
            Handler    = $null
            Visibility = "Visible"
        }

        $Item | Add-Member -MemberType ScriptMethod -Name "Add_Expanded" -Value {
            param($ScriptBlock)
            $this.Handler = $ScriptBlock
        }

        return $Item
    }

    $script:FetchCalls = [System.Collections.Generic.List[object]]::new()

    function Get-SqlSchemaObject {
        param(
            [string]$DataConnectionDoId,
            [string]$DataConnectionName
        )
        $script:FetchCalls.Add([pscustomobject]@{ DoId = $DataConnectionDoId; Name = $DataConnectionName })
    }

    function Update-SqlSchemaTreeFilter { }

    function New-SchemaResponse {
        param([hashtable]$Table)

        $Payload = [PSCustomObject]@{}
        foreach ($Key in $Table.Keys) {
            $Payload | Add-Member -MemberType NoteProperty -Name $Key -Value $Table[$Key]
        }

        return [PSCustomObject]@{ d = $Payload }
    }

    function Initialize-TreeTestState {
        $Script:TreeViewSqlSchema = [PSCustomObject]@{ Items = [System.Collections.Generic.List[object]]::new() }
        $Script:AppConfig = [PSCustomObject]@{
            CurrentDataConnection = [PSCustomObject]@{ DoId = "1001572"; FullName = "OISES - 1001572" }
        }
        $script:FetchCalls.Clear()
    }

    function Get-Node {
        param([string]$Header)
        return $Script:TreeViewSqlSchema.Items | Where-Object { $_.Header -eq $Header }
    }
}

Describe "Update-SqlSchemaDatabaseTree" {
    BeforeEach {
        Initialize-TreeTestState
    }

    It "puts one node on the tree per data connection" {
        Update-SqlSchemaDatabaseTree

        @($Script:TreeViewSqlSchema.Items.Header) | Should -Be @("OISES", "Reporting")
    }

    It "carries the DoId on the node, which is how a response finds it" {
        Update-SqlSchemaDatabaseTree

        (Get-Node -Header "Reporting").Tag.DoId | Should -Be "1001999"
    }

    It "expands the active connection and leaves every other one collapsed" {
        # "The currently selected database is expanded and populated exactly as today, so the window
        # looks unchanged for anyone not using the feature."
        Update-SqlSchemaDatabaseTree

        (Get-Node -Header "OISES").IsExpanded | Should -BeTrue
        (Get-Node -Header "Reporting").IsExpanded | Should -BeFalse
    }

    It "gives a collapsed node a placeholder child, so it has something to expand" {
        Update-SqlSchemaDatabaseTree

        (Get-Node -Header "Reporting").Items.Count | Should -Be 1
    }

    It "fetches nothing (criterion 3: opening the window costs what it did before)" {
        # The whole point of the lazy design. A tenant with a dozen connections must not pay a dozen
        # authenticated round trips for opening a window.
        Update-SqlSchemaDatabaseTree

        $script:FetchCalls.Count | Should -Be 0
    }

    It "marks the active connection as already requested" {
        # Its schema is being fetched by the normal path. Without this, expanding it would dispatch a
        # second, duplicate request for the database the window is loading anyway.
        Update-SqlSchemaDatabaseTree

        (Get-Node -Header "OISES").Tag.Requested | Should -BeTrue
        (Get-Node -Header "Reporting").Tag.Requested | Should -BeFalse
    }

    It "is idempotent: a second call adds nothing" {
        Update-SqlSchemaDatabaseTree
        Update-SqlSchemaDatabaseTree

        $Script:TreeViewSqlSchema.Items.Count | Should -Be 2
    }

    It "keeps a loaded database's children when it runs again" {
        # It runs on EVERY schema response, so rebuilding the level would throw away the subtree the
        # user just expanded - and, worse, lose the Loaded flag and invite a re-fetch.
        Update-SqlSchemaDatabaseTree
        $Node = Get-Node -Header "Reporting"
        Add-SqlSchemaTreeNode -Parent $Node -SchemaResponse (New-SchemaResponse -Table @{ "dbo.tblX" = @("Id int") }) | Out-Null
        $Node.Tag.Loaded = $true

        Update-SqlSchemaDatabaseTree

        $Again = Get-Node -Header "Reporting"
        $Again.Tag.Loaded | Should -BeTrue
        @($Again.Items.Header) | Should -Be @("dbo")
    }

    It "drops a node whose data connection is gone from the dropdown" {
        Update-SqlSchemaDatabaseTree
        function Get-DataConnectionOptionText { param([switch]$NoRefresh) return , @("OISES - 1001572") }

        Update-SqlSchemaDatabaseTree

        @($Script:TreeViewSqlSchema.Items.Header) | Should -Be @("OISES")
    }

    It "leaves the tree alone when the connection list is empty" {
        function Get-DataConnectionOptionText { param([switch]$NoRefresh) return , @() }

        Update-SqlSchemaDatabaseTree

        $Script:TreeViewSqlSchema.Items.Count | Should -Be 0
    }

    It "does nothing when the schema window was never opened" {
        $Script:TreeViewSqlSchema = $null

        { Update-SqlSchemaDatabaseTree } | Should -Not -Throw
    }
}

Describe "Invoke-SqlSchemaDatabaseNodeExpanded" {
    BeforeEach {
        Initialize-TreeTestState
        function Get-DataConnectionOptionText { param([switch]$NoRefresh) return , @("OISES - 1001572", "Reporting - 1001999") }
        Update-SqlSchemaDatabaseTree
        $script:FetchCalls.Clear()
    }

    It "fetches that database's schema the first time it is expanded" {
        $Node = Get-Node -Header "Reporting"

        Invoke-SqlSchemaDatabaseNodeExpanded -Sender $Node -EventArgs ([PSCustomObject]@{ Handled = $false })

        $script:FetchCalls.Count | Should -Be 1
        $script:FetchCalls[0].DoId | Should -Be "1001999"
        $script:FetchCalls[0].Name | Should -Be "Reporting"
    }

    It "does not fetch twice when it is collapsed and expanded again" {
        $Node = Get-Node -Header "Reporting"

        Invoke-SqlSchemaDatabaseNodeExpanded -Sender $Node -EventArgs ([PSCustomObject]@{ Handled = $false })
        Invoke-SqlSchemaDatabaseNodeExpanded -Sender $Node -EventArgs ([PSCustomObject]@{ Handled = $false })

        $script:FetchCalls.Count | Should -Be 1
    }

    It "does not fetch a database that is already loaded" {
        $Node = Get-Node -Header "Reporting"
        $Node.Tag.Loaded = $true
        $Node.Tag.Requested = $false

        Invoke-SqlSchemaDatabaseNodeExpanded -Sender $Node -EventArgs ([PSCustomObject]@{ Handled = $false })

        $script:FetchCalls.Count | Should -Be 0
    }

    It "does not re-enter the fetch that is already populating the active database" {
        # The active node is expanded as it is created. If this handler ran for it, it would ask for
        # the schema the window is in the middle of loading.
        $Node = Get-Node -Header "OISES"

        Invoke-SqlSchemaDatabaseNodeExpanded -Sender $Node -EventArgs ([PSCustomObject]@{ Handled = $false })

        $script:FetchCalls.Count | Should -Be 0
    }

    It "marks the event handled, so a schema node opening does not run it again" {
        # Expanded bubbles. Without this, expanding a schema INSIDE a database re-runs the handler for
        # the database node above it.
        $Node = Get-Node -Header "Reporting"
        $EventArgs = [PSCustomObject]@{ Handled = $false }

        Invoke-SqlSchemaDatabaseNodeExpanded -Sender $Node -EventArgs $EventArgs

        $EventArgs.Handled | Should -BeTrue
    }

    It "does nothing for a node with no Tag" {
        { Invoke-SqlSchemaDatabaseNodeExpanded -Sender ([PSCustomObject]@{ Tag = $null }) -EventArgs $null } | Should -Not -Throw
        $script:FetchCalls.Count | Should -Be 0
    }
}

Describe "Add-SqlSchemaTreeNode" {
    BeforeEach {
        Initialize-TreeTestState
    }

    It "builds schema -> table -> column under the parent it is given" {
        $Parent = New-SqlSchemaTreeItem -Header "Reporting"

        Add-SqlSchemaTreeNode -Parent $Parent -SchemaResponse (New-SchemaResponse -Table @{
                "dbo.tblObject" = @("Id int", "DisplayName nvarchar(50)")
            }) | Out-Null

        @($Parent.Items.Header) | Should -Be @("dbo")
        @($Parent.Items[0].Items.Header) | Should -Be @("tblObject")
        @($Parent.Items[0].Items[0].Items.Header) | Should -Be @("Id int", "DisplayName nvarchar(50)")
    }

    It "replaces the placeholder rather than appending beside it" {
        $Parent = New-SqlSchemaTreeItem -Header "Reporting"
        $Parent.Items.Add((New-SqlSchemaTreeItem -Header "Loading..." -FontSize 12))

        Add-SqlSchemaTreeNode -Parent $Parent -SchemaResponse (New-SchemaResponse -Table @{ "dbo.tblX" = @("Id int") }) | Out-Null

        @($Parent.Items.Header) | Should -Be @("dbo")
    }

    It "expands the schema level, as the three-level tree always did" {
        $Parent = New-SqlSchemaTreeItem -Header "Reporting"

        Add-SqlSchemaTreeNode -Parent $Parent -SchemaResponse (New-SchemaResponse -Table @{ "dbo.tblX" = @("Id int") }) | Out-Null

        $Parent.Items[0].IsExpanded | Should -BeTrue
    }

    It "returns the table count" {
        $Parent = New-SqlSchemaTreeItem -Header "Reporting"

        $Count = Add-SqlSchemaTreeNode -Parent $Parent -SchemaResponse (New-SchemaResponse -Table @{
                "dbo.tblA" = @("Id int")
                "dbo.tblB" = @("Id int")
                "cag.tblC" = @("Id int")
            })

        $Count | Should -Be 3
    }

    It "empties the parent for a response that carries no schema" {
        $Parent = New-SqlSchemaTreeItem -Header "Reporting"
        $Parent.Items.Add((New-SqlSchemaTreeItem -Header "Loading..." -FontSize 12))

        Add-SqlSchemaTreeNode -Parent $Parent -SchemaResponse $null | Out-Null

        $Parent.Items.Count | Should -Be 0
    }
}
