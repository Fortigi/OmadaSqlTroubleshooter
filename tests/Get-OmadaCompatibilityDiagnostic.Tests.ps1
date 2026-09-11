#Requires -Version 7.0
# Tests for the Omada compatibility pass of issue #61 (addendum, section 3) - the third validation
# pass, and the one that catches queries which are valid T-SQL, valid against the schema, and still
# wrong here.
#
# The test plan in section 3.9 is followed literally: per rule, one positive fixture, one
# already-correct negative fixture, and one near-miss proving the rule does not overreach. The four
# queries from section 3.1 appear verbatim as the OMD001 baseline, because they are the only evidence
# anyone has of the behaviour this rule describes.
#
# A rule with no fixture is a guess and does not ship. So the *Candidate* rules of section 3.2 -
# OMD002, OMD005, OMD006, OMD007, OMD014, OMD015 and OMD016 - are not in the catalogue and are not
# tested here; there is a test below asserting exactly that, so adding one without a captured tenant
# response is a deliberate act rather than an oversight.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PSScriptRoot -ChildPath "ScriptDomTestAssembly.ps1")

    . (Join-Path $PrivatePath -ChildPath "Get-SqlParserType.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlScriptFragment.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlFragmentDescendant.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlFragmentMarker.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlSchemaDiagnostic.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-OmadaCompatibilityRule.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-OmadaCompatibilityDiagnostic.ps1")

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

    function Get-CompatibilityDiagnosticFor {
        param([string]$SqlText, $RuleSeverity)

        $Parsed = Get-SqlScriptFragment -SqlText $SqlText
        if ($Parsed.Status -ne "Ok") {
            return $null
        }

        return @(Get-OmadaCompatibilityDiagnostic -Fragment $Parsed.Fragment -RuleSeverity $RuleSeverity)
    }

    function Get-RuleIdFor {
        param([string]$SqlText)
        return @(Get-CompatibilityDiagnosticFor -SqlText $SqlText | ForEach-Object { $_.RuleId })
    }
}

Describe 'Get-OmadaCompatibilityRule' -Tag 'Unit' {

    It 'Should ship only the rules issue #61 section 3.2 marks as claimed' {
        # The candidates need a captured tenant response before they earn a severity. This test is the
        # gate: adding one here without a fixture is then a deliberate act, not an oversight.
        @(Get-OmadaCompatibilityRule).Id | Should -Be @("OMD001", "OMD003", "OMD004", "OMD010", "OMD011", "OMD012", "OMD013")
    }

    It 'Should give every rule an id, a number matching it, a title, a severity and a predicate' {
        foreach ($Rule in @(Get-OmadaCompatibilityRule)) {
            $Rule.Id | Should -Match '^OMD\d{3}$'
            $Rule.Number | Should -Be ([int]($Rule.Id -replace '^OMD', ''))
            $Rule.Title | Should -Not -BeNullOrEmpty
            $Rule.Severity | Should -BeIn @("Error", "Warning", "Info")
            $Rule.Find | Should -BeOfType [scriptblock]
        }
    }

    It 'Should give <Id> the severity issue #61 section 3.2 assigns it' -ForEach @(
        @{ Id = 'OMD001'; Severity = 'Warning' }
        @{ Id = 'OMD003'; Severity = 'Info' }
        @{ Id = 'OMD004'; Severity = 'Error' }
        @{ Id = 'OMD010'; Severity = 'Error' }
        @{ Id = 'OMD011'; Severity = 'Error' }
        @{ Id = 'OMD012'; Severity = 'Error' }
        @{ Id = 'OMD013'; Severity = 'Error' }
    ) {
        (@(Get-OmadaCompatibilityRule) | Where-Object { $_.Id -eq $Id }).Severity | Should -Be $Severity
    }
}

Describe 'Get-OmadaCompatibilityDiagnostic' -Tag 'Unit' {

    BeforeEach {
        $script:LoggedMessage.Clear()

        if ($null -eq $script:ScriptDomPath) {
            Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
        }
    }

    Context 'OMD001 - a result column with no name' {

        It 'Should raise OMD001 on the unaliased aggregate (acceptance criterion A1)' {
            # Section 3.1, verbatim. This pair is the whole of the evidence for this rule.
            $Diagnostic = Get-CompatibilityDiagnosticFor -SqlText @"
SELECT uid, COUNT(*)
FROM   dbo.SomeTable
GROUP BY uid
"@

            $Diagnostic.Count | Should -Be 1
            $Diagnostic[0].RuleId | Should -Be "OMD001"
            $Diagnostic[0].Number | Should -Be 1
            $Diagnostic[0].Severity | Should -Be "Warning"
            $Diagnostic[0].Source | Should -Be "Omada compatibility"
            $Diagnostic[0].Line | Should -Be 1
            $Diagnostic[0].Column | Should -Be 13 -Because "the marker sits on COUNT(*), not on the statement"
        }

        It 'Should raise nothing for the aliased variant (acceptance criterion A2)' {
            (Get-CompatibilityDiagnosticFor -SqlText @"
SELECT uid, COUNT(*) AS [Count]
FROM   dbo.SomeTable
GROUP BY uid
"@).Count | Should -Be 0
        }

        It 'Should raise OMD001 on the unaliased literal (acceptance criterion A3)' {
            $Diagnostic = Get-CompatibilityDiagnosticFor -SqlText @"
SELECT id, 'test'
FROM   graphql.IdentityView
GROUP BY id
"@

            $Diagnostic.Count | Should -Be 1
            $Diagnostic[0].RuleId | Should -Be "OMD001"
        }

        It 'Should raise nothing for the aliased literal variant (acceptance criterion A3)' {
            (Get-CompatibilityDiagnosticFor -SqlText @"
SELECT id, 'test' AS [value]
FROM   graphql.IdentityView
GROUP BY id
"@).Count | Should -Be 0
        }

        It 'Should raise nothing for plain column references (acceptance criterion A4)' {
            (Get-CompatibilityDiagnosticFor -SqlText "SELECT a.Id, a.Number FROM dbo.A a").Count | Should -Be 0
        }

        It 'Should name the symptom, not just the rule (acceptance criterion A6)' {
            # The user has already seen "Query did not return any results!". The message has to connect
            # to that, or it explains nothing.
            $Diagnostic = Get-CompatibilityDiagnosticFor -SqlText "SELECT uid, COUNT(*) FROM dbo.T GROUP BY uid"

            $Diagnostic[0].Message | Should -Match "Omada returns no rows"
            $Diagnostic[0].Message | Should -Match "AS \[Count\]" -Because "the suggestion is derived from the expression"
        }

        It 'Should suggest <Suggestion> for <Label>' -ForEach @(
            @{ Label = 'an aggregate'; Text = 'SELECT COUNT(*) FROM dbo.T'; Suggestion = 'Count' }
            @{ Label = 'a literal'; Text = "SELECT 'x' FROM dbo.T"; Suggestion = 'Value' }
            @{ Label = 'a CASE'; Text = 'SELECT CASE WHEN 1 = 1 THEN 2 ELSE 3 END FROM dbo.T'; Suggestion = 'Case' }
            @{ Label = 'an arithmetic expression'; Text = 'SELECT 1 + 1 FROM dbo.T'; Suggestion = 'Column' }
        ) {
            (Get-CompatibilityDiagnosticFor -SqlText $Text)[0].Message | Should -Match ([regex]::Escape("AS [$Suggestion]"))
        }

        It 'Should flag the first branch of a UNION, which is where the result names come from' {
            (Get-RuleIdFor "SELECT COUNT(*) FROM dbo.A UNION ALL SELECT Id FROM dbo.B") | Should -Be @("OMD001")
        }

        Context 'Acceptance criterion A5: zero false positives' {
            It 'Should raise nothing for <Label>' -ForEach @(
                @{ Label = 'SELECT *'; Text = 'SELECT * FROM dbo.Person' }
                @{ Label = 'a qualified star'; Text = 'SELECT p.* FROM dbo.Person p' }
                @{ Label = 'IF EXISTS (SELECT 1 ...)'; Text = 'IF EXISTS (SELECT 1 FROM dbo.Person) SELECT 1 AS ok' }
                @{ Label = 'DECLARE @x INT = (SELECT COUNT(*) ...)'; Text = 'DECLARE @x INT = (SELECT COUNT(*) FROM dbo.Person)' }
                @{ Label = 'a nameless column in a WHERE subquery'; Text = 'SELECT p.Id FROM dbo.Person p WHERE p.Id IN (SELECT c.PersonId FROM dbo.Contract c)' }
                @{ Label = 'a UNION whose first branch names every column'; Text = 'SELECT Id AS a FROM dbo.A UNION ALL SELECT COUNT(*) FROM dbo.B' }
                @{ Label = 'an aggregate with an alias'; Text = 'SELECT MAX(p.Id) AS newest FROM dbo.Person p' }
            ) {
                @(Get-CompatibilityDiagnosticFor -SqlText $Text | Where-Object { $_.RuleId -eq "OMD001" }).Count |
                    Should -Be 0 -Because "'$Label' is legal and harmless (acceptance criterion A5)"
            }

            It 'Should raise only OMD010 for INSERT ... SELECT COUNT(*), never OMD001' {
                # The nameless column here never reaches Omada as a result set. The INSERT is the
                # problem; saying anything about the column as well would be noise on top of it.
                Get-RuleIdFor "INSERT INTO dbo.T (a) SELECT COUNT(*) FROM dbo.Person" | Should -Be @("OMD010")
            }
        }
    }

    Context 'OMD003 - an alias the result grid renames' {

        It 'Should raise OMD003 at Info on an alias with a space' {
            $Diagnostic = Get-CompatibilityDiagnosticFor -SqlText "SELECT DisplayName AS [Full Name] FROM dbo.Person"

            $Diagnostic.Count | Should -Be 1
            $Diagnostic[0].RuleId | Should -Be "OMD003"
            $Diagnostic[0].Severity | Should -Be "Info"
            $Diagnostic[0].Message | Should -Match "underscore"
        }

        It 'Should raise OMD003 on an alias with a dot' {
            (Get-RuleIdFor "SELECT DisplayName AS [a.b] FROM dbo.Person") | Should -Be @("OMD003")
        }

        It 'Should raise nothing for an alias the grid keeps unchanged' {
            (Get-CompatibilityDiagnosticFor -SqlText "SELECT DisplayName AS full_name-2 FROM dbo.Person").Count | Should -Be 0
        }

        It 'Should raise nothing for a plain unaliased column, which is named by the column' {
            (Get-CompatibilityDiagnosticFor -SqlText "SELECT p.DisplayName FROM dbo.Person p").Count | Should -Be 0
        }
    }

    Context 'OMD004 - a nameless column where SQL Server itself requires one' {

        It 'Should raise OMD004 at Error inside a CTE' {
            $Diagnostic = Get-CompatibilityDiagnosticFor -SqlText "WITH c AS (SELECT COUNT(*) FROM dbo.Person) SELECT * FROM c"

            $Diagnostic.Count | Should -Be 1
            $Diagnostic[0].RuleId | Should -Be "OMD004"
            $Diagnostic[0].Severity | Should -Be "Error"
            $Diagnostic[0].Message | Should -Match "Msg 8155"
        }

        It 'Should raise OMD004 inside a derived table' {
            (Get-RuleIdFor "SELECT d.x FROM (SELECT COUNT(*) FROM dbo.Person) d") | Should -Be @("OMD004")
        }

        It 'Should raise nothing for a CTE that declares its column list' {
            # The names are given there, so the column is not nameless.
            (Get-CompatibilityDiagnosticFor -SqlText "WITH c (n) AS (SELECT COUNT(*) FROM dbo.Person) SELECT * FROM c").Count | Should -Be 0
        }

        It 'Should raise nothing for a derived table whose columns are all aliased' {
            (Get-CompatibilityDiagnosticFor -SqlText "SELECT d.n FROM (SELECT COUNT(*) AS n FROM dbo.Person) d").Count | Should -Be 0
        }
    }

    Context 'OMD010 and OMD011 - the read-only boundary (acceptance criterion A11)' {

        It 'Should raise <Rule> on the statement keyword for <Label>' -ForEach @(
            @{ Label = 'INSERT'; Rule = 'OMD010'; Text = 'INSERT INTO dbo.T (a) VALUES (1)' }
            @{ Label = 'UPDATE'; Rule = 'OMD010'; Text = 'UPDATE dbo.T SET a = 1' }
            @{ Label = 'DELETE'; Rule = 'OMD010'; Text = 'DELETE FROM dbo.T' }
            @{ Label = 'MERGE'; Rule = 'OMD010'; Text = 'MERGE dbo.T AS t USING dbo.S AS s ON t.a = s.a WHEN MATCHED THEN UPDATE SET t.b = s.b;' }
            @{ Label = 'TRUNCATE'; Rule = 'OMD010'; Text = 'TRUNCATE TABLE dbo.T' }
            @{ Label = 'CREATE'; Rule = 'OMD011'; Text = 'CREATE VIEW v AS SELECT 1 AS a' }
            @{ Label = 'ALTER'; Rule = 'OMD011'; Text = 'ALTER TABLE dbo.T ADD b INT' }
            @{ Label = 'DROP'; Rule = 'OMD011'; Text = 'DROP TABLE dbo.T' }
        ) {
            $Diagnostic = Get-CompatibilityDiagnosticFor -SqlText $Text

            @($Diagnostic | Where-Object { $_.RuleId -eq $Rule }).Count | Should -Be 1
            $Diagnostic[0].Severity | Should -Be "Error"
            $Diagnostic[0].Line | Should -Be 1
            $Diagnostic[0].Column | Should -Be 1 -Because "the marker sits on the statement keyword"
        }

        It 'Should name read-only access as the reason (acceptance criterion A11)' {
            (Get-CompatibilityDiagnosticFor -SqlText "UPDATE dbo.T SET a = 1")[0].Message | Should -Match "read access only"
        }

        It 'Should see a write nested inside an IF block' {
            (Get-RuleIdFor "IF 1 = 1 BEGIN UPDATE dbo.T SET a = 1 END") | Should -Be @("OMD010")
        }
    }

    Context 'OMD012 - stored procedures and dynamic SQL (acceptance criterion A12)' {

        It 'Should raise OMD012 for <Label>' -ForEach @(
            @{ Label = 'EXEC dbo.SomeProc'; Text = 'EXEC dbo.SomeProc' }
            @{ Label = 'EXECUTE(@sql)'; Text = 'DECLARE @sql NVARCHAR(10); EXECUTE(@sql)' }
            @{ Label = 'sp_executesql'; Text = "EXEC sp_executesql N'SELECT 1'" }
        ) {
            @(Get-CompatibilityDiagnosticFor -SqlText $Text | Where-Object { $_.RuleId -eq "OMD012" }).Count | Should -Be 1
        }

        It 'Should raise nothing for a SELECT calling a built-in function' {
            # The near-miss: a function call is not an EXEC.
            (Get-CompatibilityDiagnosticFor -SqlText "SELECT GETDATE() AS now FROM dbo.T").Count | Should -Be 0
        }
    }

    Context 'OMD013 - temporary tables (acceptance criterion A13)' {

        It 'Should raise OMD013 for SELECT ... INTO #t' {
            $Diagnostic = Get-CompatibilityDiagnosticFor -SqlText "SELECT Id AS Id INTO #t FROM dbo.Person"

            @($Diagnostic | Where-Object { $_.RuleId -eq "OMD013" }).Count | Should -Be 1
        }

        It 'Should raise OMD013 for a reference to <Label>' -ForEach @(
            @{ Label = '#t'; Text = 'SELECT t.a FROM #t t' }
            @{ Label = '##t'; Text = 'SELECT t.a FROM ##t t' }
        ) {
            @(Get-CompatibilityDiagnosticFor -SqlText $Text | Where-Object { $_.RuleId -eq "OMD013" }).Count | Should -Be 1
        }

        It 'Should point at the CTE alternative (acceptance criterion A13)' {
            $Diagnostic = @(Get-CompatibilityDiagnosticFor -SqlText "SELECT t.a FROM #t t" | Where-Object { $_.RuleId -eq "OMD013" })
            $Diagnostic[0].Message | Should -Match "common table expression"
        }

        It 'Should raise nothing for a permanent table whose name merely contains a hash' {
            # The near-miss: the rule is about the leading #, which is what makes a table temporary.
            (Get-CompatibilityDiagnosticFor -SqlText "SELECT t.a FROM dbo.[Tag#List] t").Count | Should -Be 0
        }
    }

    Context 'Acceptance criteria A14 and A15: what must never be flagged' {

        It 'Should raise nothing at all for a multi-CTE query including a nested CTE joined to a view' {
            # A14. CTEs are the sanctioned replacement for the temp tables OMD013 rejects, so a false
            # positive here takes away the only workaround the user has.
            (Get-CompatibilityDiagnosticFor -SqlText @"
WITH c AS (SELECT Id AS Id FROM dbo.Person),
     n AS (SELECT c.Id FROM c),
     m AS (SELECT n.Id FROM n JOIN graphql.IdentityView v ON v.id = n.Id)
SELECT m.Id FROM m
"@).Count | Should -Be 0
        }

        It 'Should raise nothing for a read-only SELECT that merely contains write keywords as text' {
            # A15. The rules are AST predicates, never text matches - which is why this passes and a
            # regex-based implementation could not.
            (Get-CompatibilityDiagnosticFor -SqlText "SELECT 'update' AS [delete], p.DisplayName AS create_x FROM dbo.Person p WHERE p.DisplayName = 'drop table #t'").Count |
                Should -Be 0
        }

        It 'Should raise nothing for the supported constructs of section 3.10: <Label>' -ForEach @(
            @{ Label = 'a JOIN'; Text = 'SELECT p.Id FROM dbo.Person p JOIN dbo.Contract c ON c.PersonId = p.Id' }
            @{ Label = 'CROSS APPLY'; Text = 'SELECT p.Id, x.q FROM dbo.Person p CROSS APPLY (SELECT 1 AS q) x' }
            @{ Label = 'a set operator'; Text = 'SELECT Id AS a FROM dbo.A EXCEPT SELECT Id AS a FROM dbo.B' }
            @{ Label = 'a window function'; Text = 'SELECT ROW_NUMBER() OVER (ORDER BY p.Id) AS rn FROM dbo.Person p' }
            @{ Label = 'PIVOT'; Text = 'SELECT pv.a FROM (SELECT Id, DisplayName FROM dbo.Person) s PIVOT (COUNT(Id) FOR DisplayName IN ([a])) pv' }
            @{ Label = 'CASE with an alias'; Text = 'SELECT CASE WHEN p.Deleted = 1 THEN 1 ELSE 0 END AS gone FROM dbo.Person p' }
            @{ Label = 'a read from a view'; Text = 'SELECT v.name FROM graphql.IdentityView v' }
        ) {
            (Get-CompatibilityDiagnosticFor -SqlText $Text).Count | Should -Be 0 -Because "'$Label' is explicitly supported (section 3.2)"
        }
    }

    Context 'Configuration (acceptance criteria A7 and 3.6)' {

        It 'Should apply a per-rule severity override' {
            $Diagnostic = Get-CompatibilityDiagnosticFor -SqlText "SELECT COUNT(*) FROM dbo.T" -RuleSeverity ([PSCustomObject]@{ OMD001 = "Error" })

            $Diagnostic.Count | Should -Be 1
            $Diagnostic[0].Severity | Should -Be "Error"
        }

        It 'Should raise nothing for a rule set to Off' {
            (Get-CompatibilityDiagnosticFor -SqlText "SELECT COUNT(*) FROM dbo.T" -RuleSeverity ([PSCustomObject]@{ OMD001 = "Off" })).Count | Should -Be 0
        }

        It 'Should leave other rules alone when one is switched off' {
            $Severity = [PSCustomObject]@{ OMD001 = "Off" }
            (Get-RuleIdFor "UPDATE dbo.T SET a = 1") | Should -Be @("OMD010")
            @(Get-CompatibilityDiagnosticFor -SqlText "UPDATE dbo.T SET a = 1" -RuleSeverity $Severity).Count | Should -Be 1
        }

        It 'Should accept the override as a hashtable as well as an object' {
            (Get-CompatibilityDiagnosticFor -SqlText "SELECT COUNT(*) FROM dbo.T" -RuleSeverity @{ OMD001 = "Off" }).Count | Should -Be 0
        }

        It 'Should keep the default severity for an unrecognised override value' {
            # A typo in a configuration file must not silently switch a rule off.
            $Diagnostic = Get-CompatibilityDiagnosticFor -SqlText "SELECT COUNT(*) FROM dbo.T" -RuleSeverity ([PSCustomObject]@{ OMD001 = "Offf" })

            $Diagnostic.Count | Should -Be 1
            $Diagnostic[0].Severity | Should -Be "Warning"
        }

        It 'Should keep every default when there is no override at all' {
            (Get-CompatibilityDiagnosticFor -SqlText "SELECT COUNT(*) FROM dbo.T" -RuleSeverity $null)[0].Severity | Should -Be "Warning"
        }
    }

    Context 'Robustness' {
        It 'Should return no diagnostics for a null fragment' {
            @(Get-OmadaCompatibilityDiagnostic -Fragment $null).Count | Should -Be 0
        }

        It 'Should order the diagnostics by position' {
            $Diagnostic = Get-CompatibilityDiagnosticFor -SqlText "SELECT COUNT(*) FROM dbo.T`r`nUPDATE dbo.T SET a = 1"

            $Diagnostic.Count | Should -Be 2
            $Diagnostic[0].Line | Should -Be 1
            $Diagnostic[1].Line | Should -Be 2
        }
    }

    Context 'Logging and redaction (acceptance criterion A10)' {
        It 'Should never write the query, an identifier from it, or a rule message to the log' {
            # Rule messages quote the user's own expressions, so they follow exactly the same rule as
            # parse messages.
            $null = Get-CompatibilityDiagnosticFor -SqlText "SELECT COUNT(*) FROM dbo.Zqx7SecretTable WHERE Note = 'password=hunter2'"

            @($script:LoggedMessage).Count | Should -BeGreaterThan 0 -Because "the pass does log a count, so an empty log would pass this test for the wrong reason"

            foreach ($Entry in $script:LoggedMessage) {
                $Entry.Message | Should -Not -Match 'Zqx7'
                $Entry.Message | Should -Not -Match 'hunter2'
                $Entry.Message | Should -Not -Match 'SELECT'
                $Entry.Message | Should -Not -Match 'has no name'
            }
        }

        It 'Should log nothing above DEBUG' {
            $null = Get-CompatibilityDiagnosticFor -SqlText "UPDATE dbo.T SET a = 1"

            foreach ($Entry in $script:LoggedMessage) {
                $Entry.LogType | Should -BeIn @("DEBUG", "VERBOSE", "VERBOSE2")
            }
        }

        It 'Should carry no tracer preamble that would trace the query text' {
            foreach ($File in @("Get-OmadaCompatibilityDiagnostic.ps1", "Get-OmadaCompatibilityRule.ps1")) {
                $Source = Get-Content -Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "src\Lib\Functions\Private\$File") -Raw
                $Source | Should -Not -Match 'Tracer::WriteLine' -Because "$File is on the debounced validation path"
            }
        }
    }

    Context 'Cost' {
        It 'Should apply the whole catalogue well inside the debounce interval' {
            $Query = "SELECT TOP 100 p.Id, p.DisplayName, c.Number FROM dbo.Person AS p INNER JOIN dbo.Contract AS c ON c.PersonId = p.Id WHERE p.Deleted = 0 ORDER BY p.Id DESC;"

            $null = Get-CompatibilityDiagnosticFor -SqlText $Query

            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $Diagnostic = Get-CompatibilityDiagnosticFor -SqlText $Query
            $Stopwatch.Stop()

            $Diagnostic.Count | Should -Be 0
            $Stopwatch.Elapsed.TotalMilliseconds | Should -BeLessThan 400
        }
    }
}
