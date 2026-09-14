#Requires -Version 7.0
# Issue #120: the clipboard text for a result set whose cells are all STRINGS.
#
# The existing Format-QueryResultSelection.Tests.ps1 runs against the typed mock fixture, where "Id"
# arrives as a JSON number. That is why every acceptance criterion of #103 passed while the feature
# was quoting integers against a real tenant: with a typed response, the CLR type of the value is a
# perfectly good type source, and it is the only one PR #106 delivered.
#
# These tests use tests/fixtures/sqldataproducer.untyped.json, which is the same result set with
# every cell carried as a JSON string. Each criterion is asserted twice where both are meaningful:
#
#   * WITH SCHEMA    - the declared SQL type resolved by Get-QueryColumnSqlTypeMap, which is what
#                      priority 1 now populates.
#   * WITHOUT SCHEMA - no declared type at all, which is what an aliased or expression column gets,
#                      and where the per-column promotion of priority 3 is the only source left.
#
# Where the two answers differ, the test says so rather than testing only the flattering one.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Resolve-StrictBoolean.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-QueryResultValueKind.ps1")
    . (Join-Path $PrivatePath -ChildPath "ConvertTo-SqlLiteral.ps1")
    . (Join-Path $PrivatePath -ChildPath "ConvertTo-PowerShellLiteral.ps1")
    . (Join-Path $PrivatePath -ChildPath "Format-QueryResultSelection.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    $Script:LoggedMessage = [System.Collections.Generic.List[object]]::new()

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType = "INFO",
            $ErrorObject,
            [switch]$SkipDialog,
            [switch]$TabScoped
        )
        process {
            $Script:LoggedMessage.Add([PSCustomObject]@{ Message = [string]$Message; LogType = $LogType })
        }
    }

    function New-Setting {
        param(
            [bool]$UseColumnSchema = $true,
            [bool]$PowerShellTypedLiterals = $true,
            [string]$NullHandling = "Emit",
            [int]$MaxValues = 1000
        )

        return [PSCustomObject]@{
            UseColumnSchema         = $UseColumnSchema
            PowerShellTypedLiterals = $PowerShellTypedLiterals
            NullHandling            = $NullHandling
            MaxValues               = $MaxValues
        }
    }

    # The declared types of the mock result set, as GetSqlSchema reports them. Only these reach the
    # formatter; a column not listed here is one the schema could not resolve.
    $Script:DeclaredType = @{
        Id          = "int"
        UID         = "uniqueidentifier"
        Number      = "varchar(50)"
        DisplayName = "nvarchar(255)"
        Code        = "nvarchar(50)"
        Amount      = "decimal(18,2)"
        CreateTime  = "datetime"
        Deleted     = "bit"
        Flagged     = "bit"
        ParentID    = "int"
    }

    function New-UntypedRow {
        <#
            The untyped fixture, through ConvertFrom-Json, so every property carries exactly the CLR
            type the copy path sees for a response that renders its cells as text.
        #>
        $Path = Join-Path $PSScriptRoot -ChildPath "fixtures\sqldataproducer.untyped.json"
        return @((Get-Content -Path $Path -Raw | ConvertFrom-Json).d.Rows)
    }

    function New-ColumnSchema {
        <#
            -WithSchema populates SqlType from the declared types above; without it every column is
            left untyped, which is the state PR #106 shipped.
        #>
        param(
            [string[]]$Name,
            [switch]$WithSchema,
            [hashtable]$Override = @{},
            [bool]$AllowValuePromotion = $true
        )

        return @($Name | ForEach-Object {
                $SqlType = $null
                if ($Override.ContainsKey($_)) {
                    $SqlType = $Override[$_]
                }
                elseif ($WithSchema.IsPresent -and $Script:DeclaredType.ContainsKey($_)) {
                    $SqlType = $Script:DeclaredType[$_]
                }

                [PSCustomObject]@{
                    Header              = $_
                    PropertyName        = $_
                    SqlType             = $SqlType
                    # Get-DataGridSelectionSchema sets this from the bound rows; this fixture is the
                    # untyped response, so it is on - except where a test deliberately turns it off.
                    AllowValuePromotion = $AllowValuePromotion
                }
            })
    }

    function Get-WarningMessage {
        return @($Script:LoggedMessage | Where-Object { $_.LogType -eq "WARNING" } | ForEach-Object { $_.Message })
    }
}

Describe "Format-QueryResultSelection against an untyped response" {

    BeforeEach {
        $Script:LoggedMessage.Clear()
    }

    Context "The fixture is genuinely untyped" {
        It "carries every cell as a string, so the CLR type is no evidence of anything" {
            $Row = New-UntypedRow
            $Row.Count | Should -Be 4

            foreach ($Name in @("Id", "Code", "Amount", "Deleted", "Flagged", "Number", "DisplayName", "UID")) {
                $Row[0].$Name | Should -BeOfType [string] -Because "a live tenant renders '$Name' as text"
            }
        }

        It "is rehydrated to a [datetime] by ConvertFrom-Json even though the JSON says string" {
            # Worth pinning, because it is the one column an untyped response does NOT lose the type
            # of: ConvertFrom-Json recognises an ISO 8601 timestamp and returns a [datetime] whether
            # the JSON quoted it or not. So criterion 5 has a type source even here - as long as the
            # tenant renders the timestamp in ISO 8601. Issue #95 shows the history endpoint of the
            # same web service rendering "8/25/2026 12:03 PM" instead, and a value in that shape is
            # deliberately left quoted rather than read under a guessed culture.
            (New-UntypedRow)[0].CreateTime | Should -BeOfType [datetime]
        }
    }

    Context "The reported bug - an integer column copies as integers" {
        It "emits unquoted integers with the schema in hand (<Format>)" -ForEach @(
            @{ Format = "SqlArray"; Expected = "(`r`n    900,`r`n    901,`r`n    902,`r`n    903`r`n)" }
            @{ Format = "PowerShellArray"; Expected = "@(`r`n    900,`r`n    901,`r`n    902,`r`n    903`r`n)" }
        ) {
            Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema (New-ColumnSchema -Name "Id" -WithSchema) -OutputFormat $Format -Setting (New-Setting) |
                Should -BeExactly $Expected
        }

        It "emits unquoted integers with no schema at all, from the column's own values (<Format>)" -ForEach @(
            @{ Format = "SqlArray"; Expected = "(`r`n    900,`r`n    901,`r`n    902,`r`n    903`r`n)" }
            @{ Format = "PowerShellArray"; Expected = "@(`r`n    900,`r`n    901,`r`n    902,`r`n    903`r`n)" }
        ) {
            Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema (New-ColumnSchema -Name "Id") -OutputFormat $Format -Setting (New-Setting) |
                Should -BeExactly $Expected
        }

        It "does NOT promote when the response carried types of its own" {
            # The guard that keeps issue #103's criterion 1 true. On a typed response a JSON string
            # is evidence the column is textual, so a column of digits stays quoted there - and only
            # the rest of the payload can say which kind of response this is, which is why
            # Get-DataGridSelectionSchema decides it once from the bound rows.
            $Schema = New-ColumnSchema -Name "Id" -AllowValuePromotion $false
            Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema $Schema -OutputFormat "SqlArray" -Setting (New-Setting) |
                Should -BeExactly "(`r`n    '900',`r`n    '901',`r`n    '902',`r`n    '903'`r`n)"
        }

        It "promotes a decimal column only as a decimal, keeping its scale" {
            Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema (New-ColumnSchema -Name "Amount") -OutputFormat "SqlArray" -Setting (New-Setting) |
                Should -BeExactly "(`r`n    12.50,`r`n    0.75,`r`n    -3.20,`r`n    8.00`r`n)"
        }
    }

    Context "Acceptance criterion 1 - an nvarchar column whose values are all digits stays quoted" {
        It "keeps the declared nvarchar column quoted (<Format>)" -ForEach @(
            @{ Format = "SqlArray" }
            @{ Format = "PowerShellArray" }
        ) {
            $Actual = Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema (New-ColumnSchema -Name "Code" -WithSchema) -OutputFormat $Format -Setting (New-Setting)

            $Actual | Should -Match "'007'"
            $Actual | Should -Match "'900'"
        }

        It "keeps it quoted without a schema too, because 007 is not a canonical number" {
            $Actual = Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema (New-ColumnSchema -Name "Code") -OutputFormat "SqlArray" -Setting (New-Setting)

            $Actual | Should -Match "'900'" -Because "one non-canonical value keeps the WHOLE column a string"
        }
    }

    Context "Acceptance criterion 2 - leading zeros survive" {
        It "keeps 007 as '007' (<Format>, <Mode>)" -ForEach @(
            @{ Format = "SqlArray"; Mode = "with schema"; WithSchema = $true }
            @{ Format = "SqlArray"; Mode = "without schema"; WithSchema = $false }
            @{ Format = "PowerShellArray"; Mode = "with schema"; WithSchema = $true }
            @{ Format = "PowerShellArray"; Mode = "without schema"; WithSchema = $false }
        ) {
            $Schema = if ($WithSchema) { New-ColumnSchema -Name "Code" -WithSchema } else { New-ColumnSchema -Name "Code" }
            $Actual = Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema $Schema -OutputFormat $Format -Setting (New-Setting)

            $Actual | Should -Match "'007'"
            $Actual | Should -Not -Match "(?m)^\s+7,"
        }

        It "keeps 007 quoted even when the schema WRONGLY calls the column an int" {
            # The corroboration step. A declared type is a name-based resolution against a cache that
            # can be stale, so it is only honoured where every value bears it out - and the only int
            # literal for "007" is 7, which is a different value.
            $Schema = New-ColumnSchema -Name "Code" -Override @{ Code = "int" }
            $Actual = Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema $Schema -OutputFormat "SqlArray" -Setting (New-Setting)

            $Actual | Should -Match "'007'"
            $Actual | Should -Match "'900'"
        }
    }

    Context "Acceptance criterion 3 - no cross-column re-typing" {
        It "keeps Id numeric and Number quoted in one selection (<Mode>)" -ForEach @(
            @{ Mode = "with schema"; WithSchema = $true }
            @{ Mode = "without schema"; WithSchema = $false }
        ) {
            $Schema = if ($WithSchema) { New-ColumnSchema -Name "Id", "Number" -WithSchema } else { New-ColumnSchema -Name "Id", "Number" }
            $Actual = Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema $Schema -OutputFormat "SqlArray" -Setting (New-Setting)

            $Actual | Should -Match "\(900, 'IDG-900'\)"
            $Actual | Should -Not -Match "'900'"
        }
    }

    Context "Acceptance criterion 4 - a bit column carried as text" {
        It "copies 'False'/'True' as 0/1 for SQL" {
            Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema (New-ColumnSchema -Name "Deleted" -WithSchema) -OutputFormat "SqlArray" -Setting (New-Setting) |
                Should -BeExactly "(`r`n    0,`r`n    1,`r`n    0,`r`n    1`r`n)"
        }

        It "copies 'False'/'True' as `$false/`$true for PowerShell" {
            Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema (New-ColumnSchema -Name "Deleted" -WithSchema) -OutputFormat "PowerShellArray" -Setting (New-Setting) |
                Should -BeExactly "@(`r`n    `$false,`r`n    `$true,`r`n    `$false,`r`n    `$true`r`n)"
        }

        It "copies a bit rendered as '0'/'1' the same way" {
            Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema (New-ColumnSchema -Name "Flagged" -WithSchema) -OutputFormat "PowerShellArray" -Setting (New-Setting) |
                Should -BeExactly "@(`r`n    `$false,`r`n    `$true,`r`n    `$false,`r`n    `$true`r`n)"
        }

        It "leaves 'False' quoted when no schema says the column is a bit" {
            # Deliberate, and the honest answer: "False" is a perfectly ordinary string, and nothing
            # but a declared type distinguishes it from one. Quoted text is recoverable; an inverted
            # boolean is not.
            Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema (New-ColumnSchema -Name "Deleted") -OutputFormat "PowerShellArray" -Setting (New-Setting) |
                Should -Match "'False'"
        }
    }

    Context "Acceptance criterion 5 - ISO 8601 under any culture" {
        It "produces byte-identical output under nl-NL, en-US and tr-TR (<Format>, <Mode>)" -ForEach @(
            @{ Format = "SqlArray"; Mode = "with schema"; WithSchema = $true }
            @{ Format = "SqlArray"; Mode = "without schema"; WithSchema = $false }
            @{ Format = "PowerShellArray"; Mode = "with schema"; WithSchema = $true }
            @{ Format = "PowerShellArray"; Mode = "without schema"; WithSchema = $false }
        ) {
            $Schema = if ($WithSchema) { New-ColumnSchema -Name "CreateTime" -WithSchema } else { New-ColumnSchema -Name "CreateTime" }
            $Original = [System.Threading.Thread]::CurrentThread.CurrentCulture
            $Result = [System.Collections.Generic.List[string]]::new()

            try {
                foreach ($CultureName in @("nl-NL", "en-US", "tr-TR")) {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]::GetCultureInfo($CultureName)
                    $Result.Add((Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema $Schema -OutputFormat $Format -Setting (New-Setting)))
                }
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $Original
            }

            @($Result | Select-Object -Unique).Count | Should -Be 1
            $Result[0] | Should -Match "2019-11-20T13:55:09"
            $Result[0] | Should -Not -Match "20-11-2019"
        }
    }

    Context "Acceptance criterion 6 - NULL" {
        It "copies ParentID as NULL and warns once about IN-list semantics" {
            $Actual = Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema (New-ColumnSchema -Name "ParentID" -WithSchema) -OutputFormat "SqlArray" -Setting (New-Setting)

            $Actual | Should -BeExactly "(`r`n    NULL,`r`n    NULL,`r`n    NULL,`r`n    NULL`r`n)"
            @(Get-WarningMessage | Where-Object { $_ -match "NULL" -and $_ -match "ParentID" }).Count | Should -Be 1
        }

        It "copies ParentID as `$null for PowerShell" {
            Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema (New-ColumnSchema -Name "ParentID" -WithSchema) -OutputFormat "PowerShellArray" -Setting (New-Setting) |
                Should -BeExactly "@(`r`n    `$null,`r`n    `$null,`r`n    `$null,`r`n    `$null`r`n)"
        }
    }

    Context "Acceptance criterion 7 - the N prefix is earned, not assumed" {
        It "prefixes a value with non-ASCII characters" {
            Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema (New-ColumnSchema -Name "DisplayName" -WithSchema) -OutputFormat "SqlArray" -Setting (New-Setting) |
                Should -Match "N'Müller'"
        }

        It "does not prefix an ASCII value in a varchar column" {
            $Actual = Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema (New-ColumnSchema -Name "Number" -WithSchema) -OutputFormat "SqlArray" -Setting (New-Setting)

            $Actual | Should -Match "(?<!N)'IDG-900'"
            $Actual | Should -Not -Match "N'IDG-900'"
        }
    }

    Context "Acceptance criterion 8 - O'Brien round-trips" {
        It "doubles the quote for SQL" {
            Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema (New-ColumnSchema -Name "DisplayName" -WithSchema) -OutputFormat "SqlArray" -Setting (New-Setting) |
                Should -Match "N'O''Brien'"
        }

        It "doubles the quote for PowerShell, and the array rehydrates to the original values" {
            $Actual = Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema (New-ColumnSchema -Name "DisplayName" -WithSchema) -OutputFormat "PowerShellArray" -Setting (New-Setting)

            $Actual | Should -Match "'O''Brien'"
            @([ScriptBlock]::Create($Actual).Invoke())[3] | Should -BeExactly "O'Brien"
        }
    }

    Context "Privacy - issue #103 criterion 10" {
        It "never writes a copied value to the log" {
            foreach ($Format in @("SqlArray", "PowerShellArray")) {
                Format-QueryResultSelection -Row (New-UntypedRow) -ColumnSchema (New-ColumnSchema -Name "Id", "Code", "DisplayName" -WithSchema) -OutputFormat $Format -Setting (New-Setting) | Out-Null
            }

            foreach ($Entry in $Script:LoggedMessage) {
                $Entry.Message | Should -Not -Match "007|IDG-900|Müller|O'Brien|900"
            }
        }
    }
}
