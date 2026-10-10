BeforeAll {
    Add-Type -AssemblyName PresentationCore

    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\ConvertTo-WildcardFilterPattern.ps1")
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Update-SqlSchemaTreeFilter.ps1")

    # The tracer preamble of the function under test redacts its bound parameters.
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\ConvertTo-RedactedLogString.ps1")
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

    # Update-SqlSchemaTreeFilter only reads Header/Items/Tag and writes Visibility/IsExpanded, so the
    # tree is stubbed with plain objects. That keeps the test out of WPF's STA requirement while
    # still exercising the real visibility rules against the example schema from the feature request.
    #
    # Since issue #158 the tree has a data connection level on top, and the stub carries BOTH shapes
    # that level can be in: a database whose schema has been fetched, and one that has not. The
    # second is not an edge case - it is what every database but the selected one looks like when the
    # window opens, and it is the one the filter must not expand.
    function New-SchemaTreeStub {
        $Definition = [ordered]@{
            adhoc = @("random")
            cag   = @("ObjectTable", "DataObjectTable", "dbolist")
            dbo   = @("tblDataObjectType", "tblObject", "tblValue")
        }

        $SchemaItems = foreach ($SchemaName in $Definition.Keys) {
            $TableItems = foreach ($TableName in $Definition[$SchemaName]) {
                [PSCustomObject]@{
                    Header     = $TableName
                    Items      = @()
                    Visibility = [System.Windows.Visibility]::Visible
                    IsExpanded = $false
                }
            }

            [PSCustomObject]@{
                Header     = $SchemaName
                Items      = @($TableItems)
                Visibility = [System.Windows.Visibility]::Visible
                IsExpanded = $true
            }
        }

        $LoadedDatabase = [PSCustomObject]@{
            Header     = "OISES"
            Tag        = [PSCustomObject]@{ DoId = "1001572"; Name = "OISES"; Loaded = $true; Requested = $true }
            Items      = @($SchemaItems)
            Visibility = [System.Windows.Visibility]::Visible
            IsExpanded = $true
        }

        # Collapsed, unfetched, and holding only the placeholder that gives it an expander arrow.
        $UnloadedDatabase = [PSCustomObject]@{
            Header     = "Reporting"
            Tag        = [PSCustomObject]@{ DoId = "1001999"; Name = "Reporting"; Loaded = $false; Requested = $false }
            Items      = @(
                [PSCustomObject]@{
                    Header     = "Loading..."
                    Items      = @()
                    Visibility = [System.Windows.Visibility]::Visible
                    IsExpanded = $false
                }
            )
            Visibility = [System.Windows.Visibility]::Visible
            IsExpanded = $false
        }

        return [PSCustomObject]@{ Items = @($LoadedDatabase, $UnloadedDatabase) }
    }

    function Get-VisibleTreeLine {
        param($Tree)

        $Lines = @()
        foreach ($DatabaseItem in $Tree.Items) {
            if ($DatabaseItem.Visibility -ne [System.Windows.Visibility]::Visible) {
                continue
            }

            $Lines += $DatabaseItem.Header

            # Only a loaded database has schemas to walk; the other one's single child is the
            # placeholder, which is deliberately not part of what the filter reasons about.
            if (-not ($null -ne $DatabaseItem.Tag -and [bool]$DatabaseItem.Tag.Loaded)) {
                continue
            }

            foreach ($SchemaItem in $DatabaseItem.Items) {
                if ($SchemaItem.Visibility -ne [System.Windows.Visibility]::Visible) {
                    continue
                }

                $Lines += "  {0}" -f $SchemaItem.Header
                foreach ($TableItem in $SchemaItem.Items) {
                    if ($TableItem.Visibility -eq [System.Windows.Visibility]::Visible) {
                        $Lines += "    {0}" -f $TableItem.Header
                    }
                }
            }
        }

        return $Lines
    }

    function Get-DatabaseNode {
        param($Tree, [string]$Header)

        return $Tree.Items | Where-Object { $_.Header -eq $Header }
    }

    # Fills cached databases before a search (issue #165). It has its own suite; here it is recorded,
    # and by default fills nothing - which is the tree every Describe above was written against: a
    # database whose schema is not cached. The cache Describe below gives it something to fill.
    $script:CachedFillCalls = 0
    $script:CachedFill = $null
    function Add-SqlSchemaCachedDatabaseNode {
        $script:CachedFillCalls++
        if ($null -ne $script:CachedFill) {
            & $script:CachedFill
        }

        return 0
    }
}

Describe 'Update-SqlSchemaTreeFilter' {
    BeforeEach {
        $Script:TreeViewSqlSchema = New-SchemaTreeStub
    }

    It 'shows the whole tree when the filter is empty' {
        Update-SqlSchemaTreeFilter -FilterValue ""
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "OISES"
            "  adhoc"
            "    random"
            "  cag"
            "    ObjectTable"
            "    DataObjectTable"
            "    dbolist"
            "  dbo"
            "    tblDataObjectType"
            "    tblObject"
            "    tblValue"
            "Reporting"
        )
    }

    It 'restores the whole tree after a filter was applied' {
        Update-SqlSchemaTreeFilter -FilterValue "Object"
        Update-SqlSchemaTreeFilter -FilterValue ""
        (Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema).Count | Should -Be 12
    }

    It 'filters on "Object"' {
        Update-SqlSchemaTreeFilter -FilterValue "Object"
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "OISES"
            "  cag"
            "    ObjectTable"
            "    DataObjectTable"
            "  dbo"
            "    tblDataObjectType"
            "    tblObject"
        )
    }

    It 'filters on "tbl"' {
        Update-SqlSchemaTreeFilter -FilterValue "tbl"
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "OISES"
            "  dbo"
            "    tblDataObjectType"
            "    tblObject"
            "    tblValue"
        )
    }

    It 'filters on "Data"' {
        Update-SqlSchemaTreeFilter -FilterValue "Data"
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "OISES"
            "  cag"
            "    DataObjectTable"
            "  dbo"
            "    tblDataObjectType"
        )
    }

    It 'filters on "ctt", which spans a casing boundary' {
        Update-SqlSchemaTreeFilter -FilterValue "ctt"
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "OISES"
            "  cag"
            "    ObjectTable"
            "    DataObjectTable"
            "  dbo"
            "    tblDataObjectType"
        )
    }

    It 'shows every table of a schema whose own name matches' {
        Update-SqlSchemaTreeFilter -FilterValue "dbo"
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "OISES"
            "  cag"
            "    dbolist"
            "  dbo"
            "    tblDataObjectType"
            "    tblObject"
            "    tblValue"
        )
    }

    It 'honours an explicit wildcard typed by the user' {
        Update-SqlSchemaTreeFilter -FilterValue "tbl*Type"
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "OISES"
            "  dbo"
            "    tblDataObjectType"
        )
    }

    It 'matches case-insensitively' {
        Update-SqlSchemaTreeFilter -FilterValue "OBJECTTABLE"
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "OISES"
            "  cag"
            "    ObjectTable"
            "    DataObjectTable"
        )
    }

    It 'hides every schema when nothing matches' {
        Update-SqlSchemaTreeFilter -FilterValue "zzz"
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -BeNullOrEmpty
    }

    It 'expands the schemas that survive the filter' {
        foreach ($SchemaItem in (Get-DatabaseNode -Tree $Script:TreeViewSqlSchema -Header "OISES").Items) {
            $SchemaItem.IsExpanded = $false
        }

        Update-SqlSchemaTreeFilter -FilterValue "Data"

        $Database = Get-DatabaseNode -Tree $Script:TreeViewSqlSchema -Header "OISES"
        ($Database.Items | Where-Object { $_.Header -eq "cag" }).IsExpanded | Should -BeTrue
        ($Database.Items | Where-Object { $_.Header -eq "dbo" }).IsExpanded | Should -BeTrue
    }

    It 'reads the filter box when no filter value is passed' {
        $Script:SqlSchemaForm = [PSCustomObject]@{
            Elements = [PSCustomObject]@{
                TextBoxSchemaFilter = [PSCustomObject]@{ Text = "Data" }
            }
        }

        Update-SqlSchemaTreeFilter

        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "OISES"
            "  cag"
            "    DataObjectTable"
            "  dbo"
            "    tblDataObjectType"
        )

        $Script:SqlSchemaForm = $null
    }

    It 'does not throw when the schema window was never opened' {
        $Script:TreeViewSqlSchema = $null
        { Update-SqlSchemaTreeFilter -FilterValue "Object" } | Should -Not -Throw
    }
}

Describe 'Update-SqlSchemaTreeFilter across the data connection level (issue #158)' {
    BeforeEach {
        $Script:TreeViewSqlSchema = New-SchemaTreeStub
    }

    It 'matches a database on its own name and shows everything below it' {
        # The database level behaves like the schema level above its own children: a name hit reveals
        # the whole database rather than making the user type a second term.
        Update-SqlSchemaTreeFilter -FilterValue "OISES"

        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "OISES"
            "  adhoc"
            "    random"
            "  cag"
            "    ObjectTable"
            "    DataObjectTable"
            "    dbolist"
            "  dbo"
            "    tblDataObjectType"
            "    tblObject"
            "    tblValue"
        )
    }

    It 'keeps a database visible when only a table inside it matches' {
        Update-SqlSchemaTreeFilter -FilterValue "tblValue"

        (Get-DatabaseNode -Tree $Script:TreeViewSqlSchema -Header "OISES").Visibility |
            Should -Be ([System.Windows.Visibility]::Visible)
    }

    It 'hides a database that matches nothing' {
        Update-SqlSchemaTreeFilter -FilterValue "tblValue"

        (Get-DatabaseNode -Tree $Script:TreeViewSqlSchema -Header "Reporting").Visibility |
            Should -Be ([System.Windows.Visibility]::Collapsed)
    }

    It 'matches an unfetched database on its own name' {
        Update-SqlSchemaTreeFilter -FilterValue "Report"

        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @("Reporting")
    }

    It 'never expands an unfetched database, because expanding it is a round trip' {
        # The discriminating case for criterion 3. Expanding a database node is what dispatches its
        # schema request, so a filter that expanded every name-matching database would turn typing in
        # the filter box into one authenticated request per keystroke per database.
        Update-SqlSchemaTreeFilter -FilterValue "Report"

        (Get-DatabaseNode -Tree $Script:TreeViewSqlSchema -Header "Reporting").IsExpanded | Should -BeFalse
    }

    It 'expands a fetched database that has hits, because showing them costs nothing' {
        $Database = Get-DatabaseNode -Tree $Script:TreeViewSqlSchema -Header "OISES"
        $Database.IsExpanded = $false

        Update-SqlSchemaTreeFilter -FilterValue "tblValue"

        (Get-DatabaseNode -Tree $Script:TreeViewSqlSchema -Header "OISES").IsExpanded | Should -BeTrue
    }

    It 'does not look inside an unfetched database for matches' {
        # "Loading..." is a placeholder, not a schema. Matching it would put a database on screen
        # claiming a hit it does not have.
        Update-SqlSchemaTreeFilter -FilterValue "Loading"

        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -BeNullOrEmpty
    }

    It 'leaves a database with no Tag out rather than throwing' {
        # Defensive: a node built before its Tag was attached must not take the filter down with it.
        $Script:TreeViewSqlSchema.Items[1].Tag = $null

        { Update-SqlSchemaTreeFilter -FilterValue "Object" } | Should -Not -Throw
    }
}

Describe 'Update-SqlSchemaTreeFilter searches databases whose schema is cached (issue #165)' {
    # The preload caches every database's schema, but the window is usually opened afterwards and
    # builds those databases empty. Before this, a search never found a table in a folded database.

    BeforeEach {
        $Script:TreeViewSqlSchema = New-SchemaTreeStub
        $script:CachedFillCalls = 0

        # What the real Add-SqlSchemaCachedDatabaseNode does to the "Reporting" stub when its schema is
        # cached: the placeholder is replaced by its schemas and the node is marked loaded.
        $script:CachedFill = {
            $Reporting = $Script:TreeViewSqlSchema.Items | Where-Object { $_.Header -eq "Reporting" }
            if ($Reporting.Tag.Loaded) {
                return
            }

            $Reporting.Items = @(
                [PSCustomObject]@{
                    Header     = "rpt"
                    Items      = @(
                        [PSCustomObject]@{ Header = "CalculatedAssignment"; Items = @(); Visibility = [System.Windows.Visibility]::Visible; IsExpanded = $false }
                        [PSCustomObject]@{ Header = "Report"; Items = @(); Visibility = [System.Windows.Visibility]::Visible; IsExpanded = $false }
                    )
                    Visibility = [System.Windows.Visibility]::Visible
                    IsExpanded = $false
                }
            )
            $Reporting.Tag.Loaded = $true
            $Reporting.Tag.Requested = $true
        }
    }

    AfterAll {
        $script:CachedFill = $null
    }

    It 'finds a table inside a folded database whose schema is cached' {
        Update-SqlSchemaTreeFilter -FilterValue "Calculated"

        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "Reporting"
            "  rpt"
            "    CalculatedAssignment"
        )
    }

    It 'expands that database to show the hit' {
        Update-SqlSchemaTreeFilter -FilterValue "Calculated"

        (Get-DatabaseNode -Tree $Script:TreeViewSqlSchema -Header "Reporting").IsExpanded | Should -BeTrue
    }

    It 'fills the cached databases before a search' {
        Update-SqlSchemaTreeFilter -FilterValue "Calculated"

        $script:CachedFillCalls | Should -Be 1
    }

    It 'does not fill anything when the filter is cleared' {
        # Clearing the box must not pay for building every database.
        Update-SqlSchemaTreeFilter -FilterValue ""

        $script:CachedFillCalls | Should -Be 0
        (Get-DatabaseNode -Tree $Script:TreeViewSqlSchema -Header "Reporting").Tag.Loaded | Should -BeFalse
    }
}
