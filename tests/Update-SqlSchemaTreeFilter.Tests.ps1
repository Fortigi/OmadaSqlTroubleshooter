BeforeAll {
    Add-Type -AssemblyName PresentationCore

    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\ConvertTo-WildcardFilterPattern.ps1")
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Update-SqlSchemaTreeFilter.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { }
    }

    # Update-SqlSchemaTreeFilter only reads Header/Items and writes Visibility/IsExpanded, so the
    # tree is stubbed with plain objects. That keeps the test out of WPF's STA requirement while
    # still exercising the real visibility rules against the example schema from the feature request.
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

        return [PSCustomObject]@{ Items = @($SchemaItems) }
    }

    function Get-VisibleTreeLine {
        param($Tree)

        $Lines = @()
        foreach ($SchemaItem in $Tree.Items) {
            if ($SchemaItem.Visibility -ne [System.Windows.Visibility]::Visible) {
                continue
            }

            $Lines += $SchemaItem.Header
            foreach ($TableItem in $SchemaItem.Items) {
                if ($TableItem.Visibility -eq [System.Windows.Visibility]::Visible) {
                    $Lines += "  {0}" -f $TableItem.Header
                }
            }
        }

        return $Lines
    }
}

Describe 'Update-SqlSchemaTreeFilter' {
    BeforeEach {
        $Script:TreeViewSqlSchema = New-SchemaTreeStub
    }

    It 'shows the whole tree when the filter is empty' {
        Update-SqlSchemaTreeFilter -FilterValue ""
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "adhoc"
            "  random"
            "cag"
            "  ObjectTable"
            "  DataObjectTable"
            "  dbolist"
            "dbo"
            "  tblDataObjectType"
            "  tblObject"
            "  tblValue"
        )
    }

    It 'restores the whole tree after a filter was applied' {
        Update-SqlSchemaTreeFilter -FilterValue "Object"
        Update-SqlSchemaTreeFilter -FilterValue ""
        (Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema).Count | Should -Be 10
    }

    It 'filters on "Object"' {
        Update-SqlSchemaTreeFilter -FilterValue "Object"
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "cag"
            "  ObjectTable"
            "  DataObjectTable"
            "dbo"
            "  tblDataObjectType"
            "  tblObject"
        )
    }

    It 'filters on "tbl"' {
        Update-SqlSchemaTreeFilter -FilterValue "tbl"
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "dbo"
            "  tblDataObjectType"
            "  tblObject"
            "  tblValue"
        )
    }

    It 'filters on "Data"' {
        Update-SqlSchemaTreeFilter -FilterValue "Data"
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "cag"
            "  DataObjectTable"
            "dbo"
            "  tblDataObjectType"
        )
    }

    It 'filters on "ctt", which spans a casing boundary' {
        Update-SqlSchemaTreeFilter -FilterValue "ctt"
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "cag"
            "  ObjectTable"
            "  DataObjectTable"
            "dbo"
            "  tblDataObjectType"
        )
    }

    It 'shows every table of a schema whose own name matches' {
        Update-SqlSchemaTreeFilter -FilterValue "dbo"
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "cag"
            "  dbolist"
            "dbo"
            "  tblDataObjectType"
            "  tblObject"
            "  tblValue"
        )
    }

    It 'honours an explicit wildcard typed by the user' {
        Update-SqlSchemaTreeFilter -FilterValue "tbl*Type"
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "dbo"
            "  tblDataObjectType"
        )
    }

    It 'matches case-insensitively' {
        Update-SqlSchemaTreeFilter -FilterValue "OBJECTTABLE"
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "cag"
            "  ObjectTable"
            "  DataObjectTable"
        )
    }

    It 'hides every schema when nothing matches' {
        Update-SqlSchemaTreeFilter -FilterValue "zzz"
        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -BeNullOrEmpty
    }

    It 'expands the schemas that survive the filter' {
        foreach ($SchemaItem in $Script:TreeViewSqlSchema.Items) {
            $SchemaItem.IsExpanded = $false
        }

        Update-SqlSchemaTreeFilter -FilterValue "Data"

        ($Script:TreeViewSqlSchema.Items | Where-Object { $_.Header -eq "cag" }).IsExpanded | Should -BeTrue
        ($Script:TreeViewSqlSchema.Items | Where-Object { $_.Header -eq "dbo" }).IsExpanded | Should -BeTrue
    }

    It 'reads the filter box when no filter value is passed' {
        $Script:SqlSchemaForm = [PSCustomObject]@{
            Elements = [PSCustomObject]@{
                TextBoxSchemaFilter = [PSCustomObject]@{ Text = "Data" }
            }
        }

        Update-SqlSchemaTreeFilter

        Get-VisibleTreeLine -Tree $Script:TreeViewSqlSchema | Should -Be @(
            "cag"
            "  DataObjectTable"
            "dbo"
            "  tblDataObjectType"
        )

        $Script:SqlSchemaForm = $null
    }

    It 'does not throw when the schema window was never opened' {
        $Script:TreeViewSqlSchema = $null
        { Update-SqlSchemaTreeFilter -FilterValue "Object" } | Should -Not -Throw
    }
}
