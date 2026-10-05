#Requires -Version 7.0
# Issue #158's validation half needs the schemas of databases OTHER than the active one, and it runs
# on a debounce - on every idle tick while the user types. Issue #61's acceptance criteria 2 and 5
# say that pass makes NO request, so the single most important assertion in this file is that nothing
# here ever fetches: a database the user has not looked at is simply absent, and the pass then
# behaves exactly as it did before.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Resolve-DataConnectionReference.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-ContainedErrorLog.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlSchemaModel.ps1")
    # Get-SqlSchemaCacheKey lives here; it is the one formatter for the per-pool cache key, and
    # reading another pool's entry is one of the failures this file guards against.
    . (Join-Path $PrivatePath -ChildPath "Get-ActiveSqlSchemaModel.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-CachedSqlSchemaModelByDatabase.ps1")

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

    # Records whether the caller asked for the NON-refreshing read. The real function refreshes the
    # list from the tenant synchronously when the dropdown is empty, so a caller that forgets
    # -NoRefresh makes a request from the debounced validation path - once per idle tick. Stubbing
    # this without checking the switch would let that regression pass silently.
    $script:OptionTextCalls = [System.Collections.Generic.List[object]]::new()

    function Get-DataConnectionOptionText {
        param([switch]$NoRefresh)
        $script:OptionTextCalls.Add([pscustomobject]@{ NoRefresh = [bool]$NoRefresh })
        return , @("OISES - 1001572", "Reporting - 1001999", "Archive - 1002000")
    }

    # Every way this code could reach the tenant, counted. If any of them is called, the pass has
    # started making requests on a debounce - which is the regression this file exists to prevent.
    $script:RequestCount = 0

    function Invoke-OmadaPSWebRequestWrapper {
        $script:RequestCount++
    }

    function Invoke-OmadaPSWebRequestWrapperAsync {
        $script:RequestCount++
    }

    function Get-SqlSchemaObject {
        $script:RequestCount++
    }

    function New-SchemaResponse {
        param([hashtable]$Table)

        $Payload = [PSCustomObject]@{}
        foreach ($Key in $Table.Keys) {
            $Payload | Add-Member -MemberType NoteProperty -Name $Key -Value $Table[$Key]
        }

        return [PSCustomObject]@{ d = $Payload }
    }

    function Initialize-CacheTestState {
        $Script:RunTimeData = @{ RestMethodParam = @{ SessionKey = "pool-under-test" } }
        $Script:AppConfig = [PSCustomObject]@{
            CurrentDataConnection = [PSCustomObject]@{ DoId = "1001572"; FullName = "OISES - 1001572" }
        }
        $Script:SqlSchemaCache = @{}
        $Script:SqlSchemaModelCache = @{}
        $script:RequestCount = 0
        $script:OptionTextCalls.Clear()
    }
}

Describe "Get-CachedSqlSchemaModelByDatabase" {
    BeforeEach {
        Initialize-CacheTestState
    }

    It "returns nothing when no schema is cached" {
        (Get-CachedSqlSchemaModelByDatabase).Count | Should -Be 0
    }

    It "returns a cached database, keyed by the data connection's name in lower case" {
        # Lower case because that is how the pass looks a written database name up, and T-SQL
        # compares identifiers case-insensitively.
        $Script:SqlSchemaCache["pool-under-test|1001999"] = New-SchemaResponse -Table @{ "dbo.Invoice" = @("Id int") }

        $Model = Get-CachedSqlSchemaModelByDatabase

        $Model.Count | Should -Be 1
        $Model.ContainsKey("reporting") | Should -BeTrue
        $Model["reporting"].BySchema["dbo"].ContainsKey("Invoice") | Should -BeTrue
    }

    It "returns every cached database" {
        $Script:SqlSchemaCache["pool-under-test|1001999"] = New-SchemaResponse -Table @{ "dbo.Invoice" = @("Id int") }
        $Script:SqlSchemaCache["pool-under-test|1002000"] = New-SchemaResponse -Table @{ "dbo.Old" = @("Id int") }

        @((Get-CachedSqlSchemaModelByDatabase).Keys | Sort-Object) | Should -Be @("archive", "reporting")
    }

    It "includes the active database, so a query may name the connection it is on" {
        $Script:SqlSchemaCache["pool-under-test|1001572"] = New-SchemaResponse -Table @{ "dbo.Person" = @("Id int") }

        (Get-CachedSqlSchemaModelByDatabase).ContainsKey("oises") | Should -BeTrue
    }

    It "never makes a request for a database that is not cached" {
        # THE assertion. Three connections exist and none is cached; nothing may be fetched to find
        # out what they contain.
        Get-CachedSqlSchemaModelByDatabase | Out-Null

        $script:RequestCount | Should -Be 0
    }

    It "reads the data connection list WITHOUT letting it refresh" {
        # The other way this pass could make a request, and the less obvious one.
        # Get-DataConnectionOptionText refreshes the list from the tenant synchronously when the
        # dropdown is empty; from a debounce that is one authenticated round trip per idle tick. The
        # switch is the only thing preventing it, so the switch is asserted rather than assumed.
        $Script:SqlSchemaCache["pool-under-test|1001999"] = New-SchemaResponse -Table @{ "dbo.Invoice" = @("Id int") }

        Get-CachedSqlSchemaModelByDatabase | Out-Null

        $script:OptionTextCalls.Count | Should -BeGreaterThan 0
        @($script:OptionTextCalls | Where-Object { -not $_.NoRefresh }).Count | Should -Be 0
    }

    It "ignores a cache entry that belongs to another connection pool" {
        # Two tenants can both have a connection called "Reporting", and they are different
        # databases. Reading across pools would resolve a query against the wrong tenant's schema.
        $Script:SqlSchemaCache["another-pool|1001999"] = New-SchemaResponse -Table @{ "dbo.Invoice" = @("Id int") }

        (Get-CachedSqlSchemaModelByDatabase).Count | Should -Be 0
    }

    It "ignores a cached connection that is no longer in the dropdown" {
        $Script:SqlSchemaCache["pool-under-test|9999999"] = New-SchemaResponse -Table @{ "dbo.Gone" = @("Id int") }

        (Get-CachedSqlSchemaModelByDatabase).Count | Should -Be 0
    }

    It "memoises the index rather than rebuilding it per idle tick" {
        # Indexing a large tenant schema is thousands of string splits, and the debounce would pay
        # for it on every keystroke pause.
        $Script:SqlSchemaCache["pool-under-test|1001999"] = New-SchemaResponse -Table @{ "dbo.Invoice" = @("Id int") }

        $First = (Get-CachedSqlSchemaModelByDatabase)["reporting"]
        $Second = (Get-CachedSqlSchemaModelByDatabase)["reporting"]

        [object]::ReferenceEquals($First, $Second) | Should -BeTrue
        $Script:SqlSchemaModelCache.ContainsKey("pool-under-test|1001999") | Should -BeTrue
    }

    It "leaves out a response that indexed to nothing" {
        # Get-SqlSchemaModel returns $null for a response that produced no tables, and an empty
        # model would make every identifier in the query a miss.
        $Script:SqlSchemaCache["pool-under-test|1001999"] = [PSCustomObject]@{ d = [PSCustomObject]@{} }

        (Get-CachedSqlSchemaModelByDatabase).Count | Should -Be 0
    }

    It "returns an empty map rather than throwing when the dropdown cannot be read" {
        function Get-DataConnectionOptionText { throw "no connection list" }
        $Script:SqlSchemaCache["pool-under-test|1001999"] = New-SchemaResponse -Table @{ "dbo.Invoice" = @("Id int") }

        $Model = $null
        { $Model = Get-CachedSqlSchemaModelByDatabase } | Should -Not -Throw
        $Model.Count | Should -Be 0
    }

    It "returns an empty map when there is no connection pool yet" {
        $Script:RunTimeData = $null
        $Script:SqlSchemaCache["pool-under-test|1001999"] = New-SchemaResponse -Table @{ "dbo.Invoice" = @("Id int") }

        (Get-CachedSqlSchemaModelByDatabase).Count | Should -Be 0
    }
}
