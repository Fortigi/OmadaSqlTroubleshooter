#Requires -Version 7.0
# Tests for the schema pass of issue #61 - the second of the three validation passes described there.
#
# Two things are being proven, and the second matters more than the first. That a typo is caught is
# the feature; that a correct query is left alone is what decides whether anyone keeps the feature
# switched on. Acceptance criterion 3 is therefore a whole Context of its own, one test per construct,
# each asserting ZERO diagnostics.
#
# The schema these tests resolve against is shaped exactly like a GetSqlSchema response - an object
# whose property names are "schema.table" and whose values are "ColumnName DataType" strings - so the
# indexing under test is the indexing the application does.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PSScriptRoot -ChildPath "ScriptDomTestAssembly.ps1")

    . (Join-Path $PrivatePath -ChildPath "Get-SqlParserType.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlScriptFragment.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlFragmentDescendant.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlFragmentMarker.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlSchemaModel.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlSchemaDiagnostic.ps1")

    $script:LoggedMessage = [System.Collections.Generic.List[object]]::new()

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType = "INFO",
            $ErrorObject,
            [switch]$SkipDialog,
            [switch]$TabScoped
        )
        process {
            $script:LoggedMessage.Add([PSCustomObject]@{ Message = [string]$Message; LogType = $LogType })
        }
    }

    $script:ScriptDomPath = Install-ScriptDomForTest -RepositoryRoot $ParentPath

    # The shape a GetSqlSchema response actually has. Person and Contract deliberately share an Id
    # column, which is what makes the ambiguity case testable; graphql.IdentityView is there because
    # the schema pass must treat a view exactly like a table, and the issue's own examples use one.
    $script:SchemaResponse = [PSCustomObject]@{
        d = [PSCustomObject]@{
            "dbo.Person"           = @("Id int", "DisplayName nvarchar(50)", "Deleted bit")
            "dbo.Contract"         = @("Id int", "PersonId int", "Number nvarchar(20)")
            "graphql.IdentityView" = @("id int", "name nvarchar(50)")
            "audit.Person"         = @("Id int", "ChangedBy nvarchar(50)")
            # Owned by two schemas, NEITHER of them dbo: a bare "Event" cannot be placed from the
            # query text alone, and the two have different columns so guessing is visibly wrong.
            "audit.Event"          = @("Id int", "Actor nvarchar(50)")
            "graphql.Event"        = @("Id int", "Payload nvarchar(max)")
        }
    }

    $script:SchemaModel = Get-SqlSchemaModel -SchemaResponse $script:SchemaResponse

    function Get-SchemaDiagnosticFor {
        <#
            Parses and resolves in one step, which is what every test here wants. Returns the
            diagnostics as an array so .Count is meaningful for none, one and many alike.
        #>
        param([string]$SqlText)

        $Parsed = Get-SqlScriptFragment -SqlText $SqlText
        if ($Parsed.Status -ne "Ok") {
            return $null
        }

        return @(Get-SqlSchemaDiagnostic -Fragment $Parsed.Fragment -SchemaModel $script:SchemaModel)
    }
}

Describe 'Get-SqlSchemaModel' -Tag 'Unit' {

    It 'Should index every table in the response' {
        $script:SchemaModel.Table.Count | Should -Be 6
    }

    It 'Should split the column name from its type the way the editor does' {
        $script:SchemaModel.Table["dbo.Person"].Column["DisplayName"] | Should -Be "nvarchar(50)"
    }

    It 'Should look a table up case-insensitively, as SQL Server resolves identifiers' {
        $script:SchemaModel.BySchema["DBO"]["person"] | Should -Not -BeNullOrEmpty
        $script:SchemaModel.Table["dbo.Person"].Column.ContainsKey("displayname") | Should -BeTrue
    }

    It 'Should list every schema owning a given table name' {
        @($script:SchemaModel.ByTableName["Person"]).Count | Should -Be 2
    }

    It 'Should return nothing for <Label>, so no schema is never mistaken for an empty one' -ForEach @(
        @{ Label = 'a null response'; Response = $null }
        @{ Label = 'a response with no payload'; Response = [PSCustomObject]@{ d = $null } }
        @{ Label = 'a payload with no tables'; Response = [PSCustomObject]@{ d = [PSCustomObject]@{} } }
    ) {
        # An empty model would make every identifier in every query a miss, which is the loudest
        # possible way to be wrong.
        Get-SqlSchemaModel -SchemaResponse $Response | Should -BeNullOrEmpty
    }

    It 'Should return nothing for an error response' {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new("boom"), "id", "NotSpecified", $null)
        Get-SqlSchemaModel -SchemaResponse $ErrorRecord | Should -BeNullOrEmpty
    }
}

Describe 'Get-SqlSchemaDiagnostic' -Tag 'Unit' {

    BeforeEach {
        $script:LoggedMessage.Clear()

        if ($null -eq $script:ScriptDomPath) {
            Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
        }
    }

    Context 'When there is nothing to resolve against' {
        It 'Should return no diagnostics with no schema model' {
            # A tab whose schema has not arrived yet. The pass makes no request of its own, so this is
            # a normal state, not an error.
            $Parsed = Get-SqlScriptFragment -SqlText "SELECT Nonsense FROM dbo.NoSuchTable"
            @(Get-SqlSchemaDiagnostic -Fragment $Parsed.Fragment -SchemaModel $null).Count | Should -Be 0
        }

        It 'Should return no diagnostics with no fragment' {
            @(Get-SqlSchemaDiagnostic -Fragment $null -SchemaModel $script:SchemaModel).Count | Should -Be 0
        }
    }

    Context 'Columns' {
        It 'Should flag a column that does not exist on the aliased table' {
            # Acceptance criterion 2, verbatim: resolved through the alias, from the already-cached
            # schema, with no request to Omada.
            $Diagnostic = Get-SchemaDiagnosticFor "SELECT p.DisplaName FROM dbo.Person p"

            $Diagnostic.Count | Should -Be 1
            $Diagnostic[0].Severity | Should -Be "Warning" -Because "acceptance criterion 4: a schema finding never gates execution"
            $Diagnostic[0].Source | Should -Be "SQL schema"
            $Diagnostic[0].Line | Should -Be 1
            $Diagnostic[0].Column | Should -Be 8
            $Diagnostic[0].EndColumn | Should -Be 20 -Because "the squiggle covers the whole 'p.DisplaName' reference"
            $Diagnostic[0].Message | Should -Match "not found in the cached schema"
            $Diagnostic[0].Message | Should -Not -Match "does not exist" -Because "the cache can be stale and the schema's coverage is not guaranteed"
        }

        It 'Should say nothing about a column that does exist' {
            (Get-SchemaDiagnosticFor "SELECT p.DisplayName FROM dbo.Person p").Count | Should -Be 0
        }

        It 'Should resolve a column through the table name when there is no alias' {
            (Get-SchemaDiagnosticFor "SELECT Person.DisplayName FROM dbo.Person").Count | Should -Be 0
        }

        It 'Should flag an unqualified column that no table in the query has' {
            $Diagnostic = Get-SchemaDiagnosticFor "SELECT DisplaName FROM dbo.Person"

            $Diagnostic.Count | Should -Be 1
            $Diagnostic[0].Message | Should -Match "not found in the cached schema on any table"
        }

        It 'Should accept an unqualified column that exactly one table in the query has' {
            (Get-SchemaDiagnosticFor "SELECT Number FROM dbo.Person p JOIN dbo.Contract c ON c.PersonId = p.Id").Count | Should -Be 0
        }

        It 'Should flag an unqualified column that several tables in the query have as ambiguous' {
            $Diagnostic = Get-SchemaDiagnosticFor "SELECT Id FROM dbo.Person p JOIN dbo.Contract c ON c.PersonId = p.Id"

            $Diagnostic.Count | Should -Be 1
            $Diagnostic[0].Message | Should -Match "ambiguous"
        }

        It 'Should resolve identifiers case-insensitively' {
            (Get-SchemaDiagnosticFor "SELECT P.displayname FROM DBO.PERSON p").Count | Should -Be 0
        }

        It 'Should see through bracketed identifiers' {
            (Get-SchemaDiagnosticFor "SELECT [p].[DisplayName] FROM [dbo].[Person] AS [p]").Count | Should -Be 0
        }

        It 'Should not flag a SELECT-list alias referenced from ORDER BY' {
            # "SELECT x AS y FROM t ORDER BY y" is correct T-SQL and y is not a column of anything.
            (Get-SchemaDiagnosticFor "SELECT DisplayName AS n FROM dbo.Person ORDER BY n").Count | Should -Be 0
        }

        It 'Should resolve a correlated subquery against the outer query as well as its own' {
            (Get-SchemaDiagnosticFor "SELECT p.Id FROM dbo.Person p WHERE EXISTS (SELECT 1 FROM dbo.Contract c WHERE c.PersonId = p.Id)").Count | Should -Be 0
        }

        It 'Should skip a qualifier it cannot place rather than guessing' {
            # The qualifier belongs to no source in scope. That is not evidence of a typo - it is
            # evidence that this pass does not model whatever introduced it.
            (Get-SchemaDiagnosticFor "SELECT unknownalias.Whatever FROM dbo.Person p").Count | Should -Be 0
        }
    }

    Context 'Tables' {
        It 'Should flag a table that is not in the cached schema' {
            $Diagnostic = Get-SchemaDiagnosticFor "SELECT * FROM dbo.Peson"

            $Diagnostic.Count | Should -Be 1
            $Diagnostic[0].Severity | Should -Be "Warning"
            $Diagnostic[0].Message | Should -Match "'dbo\.Peson' is not found in the cached schema"
        }

        It 'Should flag a table that exists in another schema but not the one named' {
            (Get-SchemaDiagnosticFor "SELECT * FROM graphql.Person").Count | Should -Be 1
        }

        It 'Should accept a view exactly as it accepts a table' {
            (Get-SchemaDiagnosticFor "SELECT v.name FROM graphql.IdentityView v").Count | Should -Be 0
        }

        It 'Should accept an unqualified table name owned by exactly one schema' {
            (Get-SchemaDiagnosticFor "SELECT c.Number FROM Contract c").Count | Should -Be 0
        }

        It 'Should skip a three-part name, which this schema says nothing about' {
            (Get-SchemaDiagnosticFor "SELECT x.Whatever FROM OtherDatabase.dbo.Thing x").Count | Should -Be 0
        }

        It 'Should accept a bare table name owned by several non-dbo schemas' {
            # The table check only asks whether the object is known, and "known in some schema" is a
            # true answer to that.
            (Get-SchemaDiagnosticFor "SELECT e.Actor FROM Event e").Count | Should -Be 0
        }

        It 'Should skip COLUMN checks for a bare name owned by several non-dbo schemas' {
            # And the column check asks a question the query text cannot answer: audit.Event has
            # Actor, graphql.Event has Payload, and nothing says which one "Event" means. Validating
            # against an arbitrary pick would warn about a column that exists, or accept one that does
            # not - wrong in both directions. Both of these must therefore be silent.
            (Get-SchemaDiagnosticFor "SELECT e.Actor FROM Event e").Count | Should -Be 0
            (Get-SchemaDiagnosticFor "SELECT e.Payload FROM Event e").Count | Should -Be 0
        }

        It 'Should still check columns for a bare name only one schema owns' {
            # The discriminating half: the rule above must not switch column checking off generally.
            (Get-SchemaDiagnosticFor "SELECT c.Nope FROM Contract c").Count | Should -Be 1
        }

        It 'Should report a missing table once, not once per column of it' {
            # The columns of a table that did not resolve are unknown by definition, so reporting them
            # would be one true finding buried under several guesses.
            $Diagnostic = Get-SchemaDiagnosticFor "SELECT t.A, t.B, t.C FROM dbo.NoSuchTable t"

            $Diagnostic.Count | Should -Be 1
        }
    }

    Context 'Acceptance criterion 3: zero false positives' {
        # One test per construct, each asserting nothing at all is said. These are the queries a real
        # user writes, and a single warning on any of them is enough to get the pass switched off.
        It 'Should say nothing about <Label>' -ForEach @(
            @{ Label = 'a CTE'; Text = 'WITH c AS (SELECT Id, DisplayName FROM dbo.Person) SELECT c.Id, c.DisplayName FROM c' }
            @{ Label = 'a nested CTE'; Text = 'WITH c AS (SELECT Id FROM dbo.Person), n AS (SELECT c.Id FROM c) SELECT n.Id FROM n' }
            @{ Label = 'a derived table'; Text = 'SELECT d.Id FROM (SELECT Id FROM dbo.Person) d' }
            @{ Label = 'CROSS APPLY'; Text = 'SELECT p.Id, x.q FROM dbo.Person p CROSS APPLY (SELECT 1 AS q) x' }
            @{ Label = 'a #temp table'; Text = 'SELECT t.Anything FROM #Temp t' }
            @{ Label = 'a ##global temp table'; Text = 'SELECT t.Anything FROM ##Global t' }
            @{ Label = 'a table variable'; Text = 'DECLARE @Rows TABLE (Id int); SELECT r.Id FROM @Rows r;' }
            @{ Label = 'SELECT INTO'; Text = 'SELECT p.Id AS Id INTO #Temp FROM dbo.Person p' }
            @{ Label = 'PIVOT'; Text = 'SELECT pv.Anything FROM (SELECT Id, DisplayName FROM dbo.Person) s PIVOT (COUNT(Id) FOR DisplayName IN ([a])) pv' }
            @{ Label = 'OPENJSON'; Text = "SELECT j.a FROM OPENJSON('[]') WITH (a int) j" }
            @{ Label = 'EXEC sp_executesql'; Text = "EXEC sp_executesql N'SELECT Nonsense FROM dbo.NoSuchTable'" }
            @{ Label = 'a table-valued function'; Text = 'SELECT f.value FROM dbo.SomeFunction(1) f' }
            @{ Label = 'a UNION of two known tables'; Text = 'SELECT p.Id FROM dbo.Person p UNION ALL SELECT c.Id FROM dbo.Contract c' }
            @{ Label = 'a window function'; Text = 'SELECT p.Id, ROW_NUMBER() OVER (PARTITION BY p.Deleted ORDER BY p.Id) AS rn FROM dbo.Person p' }
            @{ Label = 'the whole corpus in one query'; Text = @"
WITH c AS (SELECT Id, DisplayName FROM dbo.Person),
     n AS (SELECT c.Id FROM c)
SELECT n.Id, d.q, t.z, v.w
FROM n
CROSS APPLY (SELECT 1 AS q) d
JOIN #Temp t ON t.z = n.Id
JOIN @Rows v ON v.w = n.Id
"@ }
        ) {
            $Diagnostic = Get-SchemaDiagnosticFor $Text
            $Diagnostic.Count | Should -Be 0 -Because "'$Label' is a construct this pass must never flag (acceptance criterion 3)"
        }

        It 'Should say nothing about a SELECT * over a known table' {
            (Get-SchemaDiagnosticFor "SELECT * FROM dbo.Person").Count | Should -Be 0
        }
    }

    Context 'Logging and redaction (issue #61 section 5)' {
        It 'Should never write the query, an identifier from it, or a diagnostic message to the log' {
            $null = Get-SchemaDiagnosticFor "SELECT Zqx7Confidential FROM dbo.Zqx7SecretTable"

            @($script:LoggedMessage).Count | Should -BeGreaterThan 0 -Because "the pass does log a count, so an empty log would pass this test for the wrong reason"

            foreach ($Entry in $script:LoggedMessage) {
                $Entry.Message | Should -Not -Match 'Zqx7'
                $Entry.Message | Should -Not -Match 'SELECT'
                $Entry.Message | Should -Not -Match 'not found in the cached schema'
            }
        }

        It 'Should log nothing above DEBUG' {
            $null = Get-SchemaDiagnosticFor "SELECT p.DisplaName FROM dbo.Person p"

            foreach ($Entry in $script:LoggedMessage) {
                $Entry.LogType | Should -BeIn @("DEBUG", "VERBOSE", "VERBOSE2")
            }
        }

        It 'Should carry no tracer preamble that would trace the query text' {
            $Source = Get-Content -Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "src\Lib\Functions\Private\Get-SqlSchemaDiagnostic.ps1") -Raw
            $Source | Should -Not -Match 'Tracer::WriteLine'
        }
    }

    Context 'Cost' {
        It 'Should resolve a realistic query well inside the debounce interval' {
            # Acceptance criterion 5. The budget is far looser than the measured cost so it fails on a
            # regression of an order of magnitude, not on a busy build agent.
            $Query = "SELECT TOP 100 p.Id, p.DisplayName, c.Number FROM dbo.Person AS p INNER JOIN dbo.Contract AS c ON c.PersonId = p.Id WHERE p.Deleted = 0 ORDER BY p.Id DESC;"

            $null = Get-SchemaDiagnosticFor $Query

            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $Diagnostic = Get-SchemaDiagnosticFor $Query
            $Stopwatch.Stop()

            $Diagnostic.Count | Should -Be 0
            $Stopwatch.Elapsed.TotalMilliseconds | Should -BeLessThan 400
        }
    }
}
