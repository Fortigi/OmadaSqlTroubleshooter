#Requires -Version 7.0
# Issue #158: the editor asks PowerShell for the schema of a database named in the query, because it
# knows the data connection NAMES (setDatabaseNames) but not their DoIds, and cannot make an
# authenticated request of its own.
#
# What matters here is that the name is resolved the SAME way the execute path resolves it. If
# completion and execution disagreed about what "[Other]" means, the editor would offer the tables of
# one database while the query ran against another - the worst possible failure for this feature, and
# an entirely silent one.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Resolve-DataConnectionReference.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-ContainedErrorLog.ps1")
    . (Join-Path $PrivatePath -ChildPath "Request-SqlSchemaForDatabase.ps1")

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

    # The dropdown, as Update-DataConnectionList leaves it. "Reporting - archive" is here on purpose:
    # it is the name that proves the entry is split from the RIGHT.
    function Get-DataConnectionOptionText {
        return , @("OISES - 1001572", "Reporting - 1001999", "Reporting - archive - 1002000")
    }

    # The fetch seam. Recorded rather than executed: whether a request is actually made is
    # Get-SqlSchemaObject's decision (it owns the cache and the in-flight check), and it has its own
    # tests. What this file asserts is WHAT it was asked for.
    $script:FetchCalls = [System.Collections.Generic.List[object]]::new()

    function Get-SqlSchemaObject {
        param(
            [string]$DataConnectionDoId,
            [string]$DataConnectionName
        )
        $script:FetchCalls.Add([pscustomobject]@{ DoId = $DataConnectionDoId; Name = $DataConnectionName })
    }
}

Describe "Request-SqlSchemaForDatabase" {
    BeforeEach {
        $script:FetchCalls.Clear()
    }

    It "fetches the schema of the data connection the name resolves to" {
        Request-SqlSchemaForDatabase -DatabaseName "Reporting"

        $script:FetchCalls.Count | Should -Be 1
        $script:FetchCalls[0].DoId | Should -Be "1001999"
        $script:FetchCalls[0].Name | Should -Be "Reporting"
    }

    It "matches the name case-insensitively, as T-SQL compares identifiers" {
        Request-SqlSchemaForDatabase -DatabaseName "rEpOrTiNg"

        $script:FetchCalls.Count | Should -Be 1
        $script:FetchCalls[0].DoId | Should -Be "1001999"
    }

    It "passes the connection's own casing on, not what the user typed" {
        # It ends up in setSchemaForDatabase, which is the key the editor's model is stored under.
        Request-SqlSchemaForDatabase -DatabaseName "rEpOrTiNg"

        $script:FetchCalls[0].Name | Should -Be "Reporting"
    }

    It "resolves a connection name that contains the separator" {
        # "Reporting - archive" really is the connection's name; its DoId is the trailing digits.
        # Splitting from the left would resolve this to the wrong database, or to none.
        Request-SqlSchemaForDatabase -DatabaseName "Reporting - archive"

        $script:FetchCalls.Count | Should -Be 1
        $script:FetchCalls[0].DoId | Should -Be "1002000"
    }

    It "does nothing for a name that matches no data connection" {
        # The user is mid-word. A half-typed name is not a defect, and the execute path already
        # reports an unresolvable database properly, with the available names.
        Request-SqlSchemaForDatabase -DatabaseName "NoSuchDatabase"

        $script:FetchCalls.Count | Should -Be 0
    }

    It "does nothing for an empty name" {
        Request-SqlSchemaForDatabase -DatabaseName ""
        Request-SqlSchemaForDatabase -DatabaseName $null

        $script:FetchCalls.Count | Should -Be 0
    }

    It "does not throw when the dropdown cannot be read" {
        # A failure to offer completions must never surface to the user: it costs hints, not work.
        function Get-DataConnectionOptionText { throw "no connection list" }

        { Request-SqlSchemaForDatabase -DatabaseName "Reporting" } | Should -Not -Throw
        $script:FetchCalls.Count | Should -Be 0
    }
}
