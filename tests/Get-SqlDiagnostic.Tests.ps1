#Requires -Version 7.0
# Tests for the one diagnostics channel of issue #61 section 3: the orchestrator that parses once and
# feeds all three passes, the rule that decides which findings take part in the execute-time
# confirmation, and the schema cache the schema pass reads.
#
# The passes themselves are covered in Get-SqlSyntaxDiagnostic.Tests.ps1,
# Get-SqlSchemaDiagnostic.Tests.ps1 and Get-OmadaCompatibilityDiagnostic.Tests.ps1. What is asserted
# here is how they combine - which is where the acceptance criteria about gating, independence and
# "no extra round trip" actually live.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PSScriptRoot -ChildPath "ScriptDomTestAssembly.ps1")

    # Reset-SqlSchemaCache is a user-initiated action rather than part of the debounced path, so it
    # carries the tracer preamble every other such function has - and the preamble needs this.
    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")

    . (Join-Path $PrivatePath -ChildPath "Get-SqlParserType.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlScriptFragment.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlDiagnosticEndColumn.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlSyntaxDiagnostic.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlFragmentDescendant.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlFragmentMarker.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlSchemaModel.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlSchemaDiagnostic.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-OmadaCompatibilityRule.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-OmadaCompatibilityDiagnostic.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-ActiveSqlSchemaModel.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlDiagnostic.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlSyntaxWarningMessage.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType = "INFO",
            $ErrorObject,
            [switch]$SkipDialog,
            [switch]$TabScoped
        )
        process { }
    }

    function Write-ContainedErrorLog {
        param([Parameter(ValueFromPipeline = $true)]$Message, $ErrorObject)
        process { }
    }

    $script:ScriptDomPath = Install-ScriptDomForTest -RepositoryRoot $ParentPath

    $script:SchemaResponse = [PSCustomObject]@{
        d = [PSCustomObject]@{
            "dbo.Person" = @("Id int", "DisplayName nvarchar(50)")
        }
    }

    $script:SchemaModel = Get-SqlSchemaModel -SchemaResponse $script:SchemaResponse

    function New-ValidationSetting {
        param(
            [bool]$Syntax = $true,
            [bool]$Schema = $true,
            [bool]$Omada = $true,
            $RuleSeverity = $null
        )

        return [PSCustomObject]@{
            Enabled                 = $Syntax
            SchemaEnabled           = $Schema
            OmadaEnabled            = $Omada
            DebounceMilliseconds    = 400
            WarnOnExecuteWithErrors = $true
            ParserVersion           = $null
            RuleSeverity            = $RuleSeverity
        }
    }
}

Describe 'Get-SqlDiagnostic' -Tag 'Unit' {

    BeforeEach {
        if ($null -eq $script:ScriptDomPath) {
            Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
        }
    }

    Context 'All three passes on one channel' {
        It 'Should return findings from every pass, ordered by position' {
            # One query, three kinds of problem: a nameless result column (OMD001), a column that is
            # not in the cached schema, and nothing wrong with the syntax.
            $Result = Get-SqlDiagnostic -SqlText "SELECT COUNT(*), p.DisplaName FROM dbo.Person p" -Setting (New-ValidationSetting) -SchemaModel $script:SchemaModel

            $Result.Status | Should -Be "Ok"
            @($Result.Diagnostic).Source | Should -Be @("Omada compatibility", "SQL schema")
            @($Result.Diagnostic)[0].Column | Should -BeLessThan @($Result.Diagnostic)[1].Column
        }

        It 'Should report the parser it used' {
            (Get-SqlDiagnostic -SqlText "SELECT 1 AS a" -Setting (New-ValidationSetting) -SchemaModel $script:SchemaModel).ParserVersion | Should -Match '^TSql\d+Parser$'
        }
    }

    Context 'Each pass switches off independently (acceptance criteria 7 and A8)' {
        It 'Should return only <Expected> when only <Label> is on' -ForEach @(
            @{ Label = 'the syntax pass'; Syntax = $true; Schema = $false; Omada = $false; Expected = @("T-SQL syntax") }
            @{ Label = 'the schema pass'; Syntax = $false; Schema = $true; Omada = $false; Expected = @("SQL schema") }
            @{ Label = 'the compatibility pass'; Syntax = $false; Schema = $false; Omada = $true; Expected = @("Omada compatibility") }
        ) {
            # A query with one finding for each pass would need to parse cleanly AND not parse
            # cleanly, so the schema and compatibility findings are asserted on a clean script and the
            # syntax finding on a broken one.
            $Setting = New-ValidationSetting -Syntax $Syntax -Schema $Schema -Omada $Omada

            $Text = if ($Syntax) { "SELECT a, FROM dbo.Person" } else { "SELECT COUNT(*), p.DisplaName FROM dbo.Person p" }
            $Result = Get-SqlDiagnostic -SqlText $Text -Setting $Setting -SchemaModel $script:SchemaModel

            @($Result.Diagnostic).Count | Should -BeGreaterThan 0
            @($Result.Diagnostic).Source | Select-Object -Unique | Should -Be $Expected
        }

        It 'Should report Disabled and check nothing when all three are off' {
            $Result = Get-SqlDiagnostic -SqlText "SELECT a, FROM dbo.Person" -Setting (New-ValidationSetting -Syntax $false -Schema $false -Omada $false)

            $Result.Status | Should -Be "Disabled"
            @($Result.Diagnostic).Count | Should -Be 0
        }
    }

    Context 'A script that does not parse' {
        It 'Should report the syntax error and stay silent about schema and compatibility' {
            # A recovered parse names identifiers the user has not finished typing. Resolving those
            # would put a warning under the cursor on every keystroke.
            $Result = Get-SqlDiagnostic -SqlText "SELECT p.DisplaName, FROM dbo.Person p" -Setting (New-ValidationSetting) -SchemaModel $script:SchemaModel

            @($Result.Diagnostic).Source | Select-Object -Unique | Should -Be @("T-SQL syntax")
        }
    }

    Context 'When the parser is unavailable (acceptance criteria 6 and A8)' {
        It 'Should report Unavailable rather than throwing' {
            $Original = ${function:Get-SqlParserType}
            try {
                Set-Item -Path "function:Get-SqlParserType" -Value { param($ParserVersion) return $null }

                $Result = Get-SqlDiagnostic -SqlText "SELECT a, FROM dbo.Person" -Setting (New-ValidationSetting) -SchemaModel $script:SchemaModel

                $Result.Status | Should -Be "Unavailable"
                @($Result.Diagnostic).Count | Should -Be 0
            }
            finally {
                Set-Item -Path "function:Get-SqlParserType" -Value $Original
            }
        }
    }

    Context 'The schema pass makes no request (acceptance criterion 5)' {
        It 'Should resolve against the cache without any request function existing at all' {
            # Discriminating: nothing in this session defines Invoke-OmadaPSWebRequestWrapper or
            # Get-SqlSchemaObject, so a pass that tried to fetch would throw CommandNotFound rather
            # than quietly succeeding.
            Get-Command -Name "Invoke-OmadaPSWebRequestWrapper" -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command -Name "Get-SqlSchemaObject" -ErrorAction SilentlyContinue | Should -BeNullOrEmpty

            $Result = Get-SqlDiagnostic -SqlText "SELECT p.DisplaName FROM dbo.Person p" -Setting (New-ValidationSetting -Omada $false) -SchemaModel $script:SchemaModel

            @($Result.Diagnostic).Count | Should -Be 1
        }
    }
}

Describe 'Test-SqlDiagnosticBlocksExecution' -Tag 'Unit' {

    # Issue #61 section 3.5 and acceptance criteria 4 and A7. Nothing here ever blocks; the answer
    # only decides whether the user is asked once.

    It 'Should ask for <Label>' -ForEach @(
        @{ Label = 'a syntax error'; Source = 'T-SQL syntax'; Severity = 'Error'; Expected = $true }
        @{ Label = 'an Omada rule at Error'; Source = 'Omada compatibility'; Severity = 'Error'; Expected = $true }
        @{ Label = 'an Omada rule at Warning'; Source = 'Omada compatibility'; Severity = 'Warning'; Expected = $true }
        @{ Label = 'an Omada rule at Info'; Source = 'Omada compatibility'; Severity = 'Info'; Expected = $false }
        @{ Label = 'a schema warning'; Source = 'SQL schema'; Severity = 'Warning'; Expected = $false }
    ) {
        Test-SqlDiagnosticBlocksExecution -Diagnostic ([PSCustomObject]@{ Source = $Source; Severity = $Severity }) | Should -Be $Expected
    }

    It 'Should say no for a null diagnostic' {
        Test-SqlDiagnosticBlocksExecution -Diagnostic $null | Should -BeFalse
    }

    It 'Should never select a schema warning out of a mixed set' {
        # Acceptance criterion 4, stated as the selection the execute path actually performs.
        $Diagnostic = @(
            [PSCustomObject]@{ Source = 'SQL schema'; Severity = 'Warning' }
            [PSCustomObject]@{ Source = 'Omada compatibility'; Severity = 'Warning' }
            [PSCustomObject]@{ Source = 'T-SQL syntax'; Severity = 'Error' }
        )

        @($Diagnostic | Where-Object { Test-SqlDiagnosticBlocksExecution -Diagnostic $_ }).Source |
            Should -Be @('Omada compatibility', 'T-SQL syntax')
    }
}

Describe 'Get-SqlSyntaxWarningMessage with mixed diagnostics' -Tag 'Unit' {

    It 'Should count the syntax errors and the compatibility problems separately' {
        $Message = Get-SqlSyntaxWarningMessage -Diagnostic @(
            [PSCustomObject]@{ Line = 2; Column = 4; Severity = 'Error'; Message = "Incorrect syntax near 'x'."; Source = 'T-SQL syntax' }
            [PSCustomObject]@{ Line = 5; Column = 1; Severity = 'Warning'; Message = 'This column has no name.'; Source = 'Omada compatibility' }
            [PSCustomObject]@{ Line = 6; Column = 1; Severity = 'Error'; Message = 'read access only'; Source = 'Omada compatibility' }
        )

        $Message | Should -Match '1 syntax error'
        $Message | Should -Match '2 Omada compatibility problems'
        $Message | Should -Match 'line 2'
    }

    It 'Should describe a compatibility-only set without mentioning syntax' {
        $Message = Get-SqlSyntaxWarningMessage -Diagnostic @(
            [PSCustomObject]@{ Line = 1; Column = 1; Severity = 'Warning'; Message = 'm'; Source = 'Omada compatibility' }
        )

        $Message | Should -Match '1 Omada compatibility problem'
        $Message | Should -Not -Match 'syntax'
    }

    It 'Should still quote no part of the query' {
        $Message = Get-SqlSyntaxWarningMessage -Diagnostic @(
            [PSCustomObject]@{ Line = 1; Column = 1; Severity = 'Warning'; Message = "The alias 'Zqx7Secret' contains characters"; Source = 'Omada compatibility' }
        )

        $Message | Should -Not -Match 'Zqx7Secret'
    }
}

Describe 'The schema model cache' -Tag 'Unit' {

    BeforeEach {
        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
        $Script:RunTimeData = @{ RestMethodParam = @{ SessionKey = "pool" } }
        $Script:AppConfig = [PSCustomObject]@{ CurrentDataConnection = [PSCustomObject]@{ DoId = "1001572" } }
        $Script:SqlSchemaCache = @{ "pool|1001572" = $script:SchemaResponse }
        $Script:SqlSchemaModelCache = $null
        $script:SchemaFetchCount = 0

        function Get-SqlSchemaObject { $script:SchemaFetchCount++ }
    }

    It 'Should build the key from the session key and the data connection' {
        Get-ActiveSqlSchemaCacheKey | Should -Be "pool|1001572"
    }

    It 'Should return no key when no data connection is selected' {
        $Script:AppConfig.CurrentDataConnection.DoId = ""
        Get-ActiveSqlSchemaCacheKey | Should -BeNullOrEmpty
    }

    It 'Should index the cached response for the active connection' {
        (Get-ActiveSqlSchemaModel).Table.ContainsKey("dbo.Person") | Should -BeTrue
    }

    It 'Should index it once and memoise the result' {
        # Indexing a tenant schema is thousands of string splits; the debounce would otherwise pay for
        # it on every idle tick.
        $First = Get-ActiveSqlSchemaModel
        $Second = Get-ActiveSqlSchemaModel

        [object]::ReferenceEquals($First, $Second) | Should -BeTrue
    }

    It 'Should return nothing when the connection has no cached schema yet' {
        $Script:SqlSchemaCache = @{}
        Get-ActiveSqlSchemaModel | Should -BeNullOrEmpty
    }

    It 'Should drop both caches and re-fetch when the schema is refreshed' {
        # The "Refresh schema" action of issue #61 section 2: a stale cache is the reason this pass
        # only ever warns, and the user needs a way to say "it changed, look again".
        $null = Get-ActiveSqlSchemaModel
        $Script:SqlSchemaModelCache.ContainsKey("pool|1001572") | Should -BeTrue

        Reset-SqlSchemaCache

        $Script:SqlSchemaCache.ContainsKey("pool|1001572") | Should -BeFalse
        $Script:SqlSchemaModelCache.ContainsKey("pool|1001572") | Should -BeFalse
        $script:SchemaFetchCount | Should -Be 1
    }

    It 'Should not fetch when there is no connection to refresh' {
        $Script:AppConfig.CurrentDataConnection.DoId = ""

        Reset-SqlSchemaCache

        $script:SchemaFetchCount | Should -Be 0
    }
}
