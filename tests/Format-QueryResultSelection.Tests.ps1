#Requires -Version 7.0
# Tests for the clipboard text that issue #103's "Copy as SQL/PowerShell array" produces.
#
# The fixture columns are the ones the issue's failure table is written against - Id int, Number
# nvarchar, Deleted bit, CreateTime datetime, ParentID NULL, UID uniqueidentifier - and the rows are
# built by deserialising the same JSON shape the SqlDataProducer endpoint returns, so the CLR types
# under test are the ones the application really sees rather than ones the test invented.

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

    # Every log line is captured rather than written, so the privacy assertions further down can
    # look at exactly what would have reached the application log.
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

    function New-ColumnSchema {
        param(
            [string[]]$Name
        )

        return @($Name | ForEach-Object {
                [PSCustomObject]@{ Header = $_; PropertyName = $_; SqlType = $null }
            })
    }

    function New-FixtureRow {
        <#
            The mock result set from tests/mock/fixtures/asmx.paging.sqldataproducer.json, taken
            through ConvertFrom-Json so every property carries the CLR type the real copy path
            would see.
        #>
        return @(
            '{ "Id": 900, "UID": "0f6a1b3c-1111-4a2b-9c01-a00000000900", "Number": "IDG-900", "CreateTime": "2019-11-20T13:55:09", "Deleted": false, "ParentID": null }',
            '{ "Id": 901, "UID": "0f6a1b3c-1111-4a2b-9c01-a00000000901", "Number": "IDG-901", "CreateTime": "2019-11-20T13:55:09", "Deleted": true,  "ParentID": null }'
        ) | ForEach-Object { $_ | ConvertFrom-Json }
    }

    function New-Row {
        param(
            [hashtable[]]$Property
        )

        return @($Property | ForEach-Object { [PSCustomObject]$_ })
    }

    function Get-WarningMessage {
        return @($Script:LoggedMessage | Where-Object { $_.LogType -eq "WARNING" } | ForEach-Object { $_.Message })
    }
}

Describe "Format-QueryResultSelection" {

    BeforeEach {
        $Script:LoggedMessage.Clear()
    }

    Context "Nothing to copy" {
        It "returns an empty string for no rows" {
            Format-QueryResultSelection -Row @() -ColumnSchema (New-ColumnSchema -Name "Id") -OutputFormat "SqlArray" -Setting (New-Setting) | Should -BeExactly ""
        }

        It "returns an empty string for no columns" {
            Format-QueryResultSelection -Row (New-FixtureRow) -ColumnSchema @() -OutputFormat "SqlArray" -Setting (New-Setting) | Should -BeExactly ""
        }
    }

    Context "Acceptance criterion 1 - an nvarchar column whose values are all digits stays quoted" {
        It "quotes them in <Format>" -ForEach @(
            @{ Format = "SqlArray"; Expected = "(`r`n    '12345',`r`n    '12346'`r`n)" }
            @{ Format = "PowerShellArray"; Expected = "@(`r`n    '12345',`r`n    '12346'`r`n)" }
        ) {
            $Row = New-Row -Property @{ Number = "12345" }, @{ Number = "12346" }
            Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Number") -OutputFormat $Format -Setting (New-Setting) | Should -BeExactly $Expected
        }
    }

    Context "Acceptance criterion 2 - leading zeros survive" {
        It "keeps 007 as 007 in <Format>" -ForEach @(
            @{ Format = "SqlArray" }
            @{ Format = "PowerShellArray" }
        ) {
            $Row = New-Row -Property @{ Code = "007" }
            $Actual = Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Code") -OutputFormat $Format -Setting (New-Setting)

            $Actual | Should -Match "'007'"
            $Actual | Should -Not -Match "(?<!')\b7\b"
        }
    }

    Context "Acceptance criterion 3 - no cross-column re-typing" {
        It "keeps Id numeric and Number quoted in the same selection (SQL)" {
            $Actual = Format-QueryResultSelection -Row (New-FixtureRow) -ColumnSchema (New-ColumnSchema -Name "Id", "Number") -OutputFormat "SqlArray" -Setting (New-Setting)

            $Actual | Should -BeExactly "(VALUES`r`n    (900, 'IDG-900'),`r`n    (901, 'IDG-901')`r`n) AS t ([Id], [Number])"
        }

        It "keeps Id numeric and Number quoted in the same selection (PowerShell)" {
            $Actual = Format-QueryResultSelection -Row (New-FixtureRow) -ColumnSchema (New-ColumnSchema -Name "Id", "Number") -OutputFormat "PowerShellArray" -Setting (New-Setting)

            $Actual | Should -BeExactly "@(`r`n    [PSCustomObject]@{ Id = 900; Number = 'IDG-900' }`r`n    [PSCustomObject]@{ Id = 901; Number = 'IDG-901' }`r`n)"
        }

        It "does not let one non-numeric column re-type the integers of another - the pre-#103 bug" {
            $Actual = Format-QueryResultSelection -Row (New-FixtureRow) -ColumnSchema (New-ColumnSchema -Name "Id", "Number") -OutputFormat "SqlArray" -Setting (New-Setting)

            $Actual | Should -Match "\(900, "
            $Actual | Should -Not -Match "'900'"
        }
    }

    Context "Acceptance criterion 4 - a bit column" {
        It "copies Deleted as 1/0 for SQL" {
            Format-QueryResultSelection -Row (New-FixtureRow) -ColumnSchema (New-ColumnSchema -Name "Deleted") -OutputFormat "SqlArray" -Setting (New-Setting) |
                Should -BeExactly "(`r`n    0,`r`n    1`r`n)"
        }

        It "copies Deleted as `$false/`$true for PowerShell" {
            Format-QueryResultSelection -Row (New-FixtureRow) -ColumnSchema (New-ColumnSchema -Name "Deleted") -OutputFormat "PowerShellArray" -Setting (New-Setting) |
                Should -BeExactly "@(`r`n    `$false,`r`n    `$true`r`n)"
        }

        It "never emits the string 'False', which is truthy in PowerShell" {
            Format-QueryResultSelection -Row (New-FixtureRow) -ColumnSchema (New-ColumnSchema -Name "Deleted") -OutputFormat "PowerShellArray" -Setting (New-Setting) |
                Should -Not -Match "'False'"
        }
    }

    Context "Acceptance criterion 5 - CreateTime is ISO 8601 under any culture" {
        It "produces byte-identical output under nl-NL, en-US and tr-TR for <Format>" -ForEach @(
            @{ Format = "SqlArray" }
            @{ Format = "PowerShellArray" }
        ) {
            $Original = [System.Threading.Thread]::CurrentThread.CurrentCulture
            $Result = [System.Collections.Generic.List[string]]::new()
            try {
                foreach ($CultureName in @("nl-NL", "en-US", "tr-TR")) {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]::GetCultureInfo($CultureName)
                    $Result.Add((Format-QueryResultSelection -Row (New-FixtureRow) -ColumnSchema (New-ColumnSchema -Name "CreateTime") -OutputFormat $Format -Setting (New-Setting)))
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
        It "copies ParentID as NULL for SQL and warns about IN-list semantics" {
            $Actual = Format-QueryResultSelection -Row (New-FixtureRow) -ColumnSchema (New-ColumnSchema -Name "ParentID") -OutputFormat "SqlArray" -Setting (New-Setting)

            $Actual | Should -BeExactly "(`r`n    NULL,`r`n    NULL`r`n)"
            @(Get-WarningMessage | Where-Object { $_ -match "NULL" -and $_ -match "ParentID" }).Count | Should -Be 1
        }

        It "copies ParentID as `$null for PowerShell" {
            Format-QueryResultSelection -Row (New-FixtureRow) -ColumnSchema (New-ColumnSchema -Name "ParentID") -OutputFormat "PowerShellArray" -Setting (New-Setting) |
                Should -BeExactly "@(`r`n    `$null,`r`n    `$null`r`n)"
        }

        It "never emits an empty string in place of a NULL" {
            Format-QueryResultSelection -Row (New-FixtureRow) -ColumnSchema (New-ColumnSchema -Name "ParentID") -OutputFormat "SqlArray" -Setting (New-Setting) |
                Should -Not -Match "''"
        }

        It "drops NULLs when ArrayCopyNullHandling is Skip" {
            $Row = New-Row -Property @{ Id = 900 }, @{ Id = $null }, @{ Id = 901 }
            Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Id") -OutputFormat "SqlArray" -Setting (New-Setting -NullHandling "Skip") |
                Should -BeExactly "(`r`n    900,`r`n    901`r`n)"
        }

        It "does not warn about IN-list semantics when the NULLs were skipped" {
            $Row = New-Row -Property @{ Id = 900 }, @{ Id = $null }
            Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Id") -OutputFormat "SqlArray" -Setting (New-Setting -NullHandling "Skip") | Out-Null

            @(Get-WarningMessage | Where-Object { $_ -match "silently excludes" }).Count | Should -Be 0
        }

        It "ignores Skip for a multi-column selection and says so, because a row constructor cannot be ragged" {
            $Row = New-Row -Property @{ Id = 900; Number = $null }
            $Actual = Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Id", "Number") -OutputFormat "SqlArray" -Setting (New-Setting -NullHandling "Skip")

            $Actual | Should -Match "NULL"
            @(Get-WarningMessage | Where-Object { $_ -match "does not apply to a multi-column selection" }).Count | Should -Be 1
        }
    }

    Context "Acceptance criterion 7 - the N prefix" {
        It "prefixes a non-ASCII value" {
            $Row = New-Row -Property @{ Name = "Müller" }
            Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Name") -OutputFormat "SqlArray" -Setting (New-Setting) |
                Should -Match "N'Müller'"
        }

        It "does not prefix an ASCII value" {
            $Row = New-Row -Property @{ Name = "Smith" }
            Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Name") -OutputFormat "SqlArray" -Setting (New-Setting) |
                Should -Not -Match "N'"
        }
    }

    Context "Acceptance criterion 8 - O'Brien" {
        It "escapes it in <Format>" -ForEach @(
            @{ Format = "SqlArray" }
            @{ Format = "PowerShellArray" }
        ) {
            $Row = New-Row -Property @{ Name = "O'Brien" }
            Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Name") -OutputFormat $Format -Setting (New-Setting) |
                Should -Match "'O''Brien'"
        }
    }

    Context "Acceptance criterion 9 - a multi-column selection parses" {
        It "produces PowerShell that parses and rehydrates to the original typed values" {
            $Actual = Format-QueryResultSelection -Row (New-FixtureRow) -ColumnSchema (New-ColumnSchema -Name "Id", "Number", "Deleted") -OutputFormat "PowerShellArray" -Setting (New-Setting)
            $RoundTrip = @(& ([ScriptBlock]::Create($Actual)))

            $RoundTrip.Count | Should -Be 2
            $RoundTrip[0].Id | Should -Be 900
            # A number, not a string. The exact integer width is whatever the PowerShell parser
            # picks for the literal and is not part of the contract; being numeric at all is.
            $RoundTrip[0].Id -is [string] | Should -BeFalse
            [System.Convert]::ToInt64($RoundTrip[0].Id) | Should -Be 900
            $RoundTrip[0].Number | Should -BeExactly "IDG-900"
            $RoundTrip[0].Deleted | Should -BeFalse
            $RoundTrip[0].Deleted | Should -BeOfType [bool]
            $RoundTrip[1].Deleted | Should -BeTrue
        }

        It "produces a single-column PowerShell array that parses to the original values" {
            $Actual = Format-QueryResultSelection -Row (New-FixtureRow) -ColumnSchema (New-ColumnSchema -Name "Id") -OutputFormat "PowerShellArray" -Setting (New-Setting)
            $RoundTrip = @(& ([ScriptBlock]::Create($Actual)))

            $RoundTrip | Should -Be @(900, 901)
        }
    }

    Context "Acceptance criterion 10 - no copied value reaches the log above DEBUG" {
        It "logs column names and counts but never a value" {
            $Row = New-Row -Property @{ Secret = "s3cret-identity-value"; Other = $null }
            Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Secret", "Other") -OutputFormat "SqlArray" -Setting (New-Setting) | Out-Null

            $AboveDebug = @($Script:LoggedMessage | Where-Object { $_.LogType -notin @("DEBUG", "VERBOSE") })
            foreach ($Entry in $AboveDebug) {
                $Entry.Message | Should -Not -Match "s3cret-identity-value"
            }
        }

        It "does not put a value in the DEBUG line either" {
            $Row = New-Row -Property @{ Secret = "s3cret-identity-value" }
            Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Secret") -OutputFormat "SqlArray" -Setting (New-Setting) | Out-Null

            foreach ($Entry in $Script:LoggedMessage) {
                $Entry.Message | Should -Not -Match "s3cret-identity-value"
            }
        }

        It "still names the column and the count, which is what makes the log useful" {
            $Row = New-Row -Property @{ Secret = "s3cret-identity-value" }
            Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Secret") -OutputFormat "SqlArray" -Setting (New-Setting) | Out-Null

            @($Script:LoggedMessage | Where-Object { $_.Message -match "Secret" }).Count | Should -BeGreaterThan 0
        }
    }

    Context "The ArrayCopyMaxValues threshold" {
        It "warns above the threshold and still produces the output" {
            $Row = @(1..5 | ForEach-Object { [PSCustomObject]@{ Id = $_ } })
            $Actual = Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Id") -OutputFormat "SqlArray" -Setting (New-Setting -MaxValues 3)

            $Actual | Should -Not -BeNullOrEmpty
            @(Get-WarningMessage | Where-Object { $_ -match "8623" }).Count | Should -Be 1
        }

        It "does not warn at or below the threshold" {
            $Row = @(1..3 | ForEach-Object { [PSCustomObject]@{ Id = $_ } })
            Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Id") -OutputFormat "SqlArray" -Setting (New-Setting -MaxValues 3) | Out-Null

            @(Get-WarningMessage | Where-Object { $_ -match "8623" }).Count | Should -Be 0
        }
    }

    Context "Per-column kind agreement" {
        It "widens a column that mixes integers and doubles instead of re-typing it as text" {
            # ConvertFrom-Json is allowed to hand back 900 as Int64 and 12.5 as Double from the same
            # decimal column. Falling back to String there would be the old bug again.
            $Row = New-Row -Property @{ Amount = [int64]900 }, @{ Amount = [double]12.5 }
            Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Amount") -OutputFormat "SqlArray" -Setting (New-Setting) |
                Should -BeExactly "(`r`n    900,`r`n    12.5`r`n)"
        }

        It "falls back to a quoted column when the kinds genuinely disagree" {
            $Row = New-Row -Property @{ Mixed = [int64]900 }, @{ Mixed = "IDG-900" }
            $Actual = Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Mixed") -OutputFormat "SqlArray" -Setting (New-Setting)

            $Actual | Should -Match "'900'"
            $Actual | Should -Match "'IDG-900'"
        }

        It "emits NULL throughout for a column that has no non-null value at all" {
            $Row = New-Row -Property @{ Empty = $null }, @{ Empty = $null }
            Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Empty") -OutputFormat "SqlArray" -Setting (New-Setting) |
                Should -BeExactly "(`r`n    NULL,`r`n    NULL`r`n)"
        }

        It "formats a later GUID row consistently with the column kind rather than throwing" {
            $Row = New-Row -Property @{ UID = "0f6a1b3c-1111-4a2b-9c01-a00000000900" }, @{ UID = "not-a-guid" }
            $Actual = Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "UID") -OutputFormat "PowerShellArray" -Setting (New-Setting)

            $Actual | Should -Match "'not-a-guid'"
            { & ([ScriptBlock]::Create($Actual)) } | Should -Not -Throw
        }
    }

    Context "Identifier escaping in the generated shapes" {
        It "brackets a column header and doubles an embedded closing bracket" {
            $Row = New-Row -Property @{ "a]b" = 1; "Id" = 2 }
            Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "a]b", "Id") -OutputFormat "SqlArray" -Setting (New-Setting) |
                Should -Match "\[a\]\]b\]"
        }

        It "quotes a PowerShell property name that is not a plain identifier" {
            $Row = New-Row -Property @{ "Order Number" = "IDG-900"; "Id" = 1 }
            $Actual = Format-QueryResultSelection -Row $Row -ColumnSchema (New-ColumnSchema -Name "Order Number", "Id") -OutputFormat "PowerShellArray" -Setting (New-Setting)

            $Actual | Should -Match "'Order Number' ="
            { & ([ScriptBlock]::Create($Actual)) } | Should -Not -Throw
        }
    }

    Context "Ordering" {
        It "emits columns in the order of the supplied schema and rows in their supplied order" {
            $Actual = Format-QueryResultSelection -Row (New-FixtureRow) -ColumnSchema (New-ColumnSchema -Name "Number", "Id") -OutputFormat "SqlArray" -Setting (New-Setting)

            $Actual | Should -BeExactly "(VALUES`r`n    ('IDG-900', 900),`r`n    ('IDG-901', 901)`r`n) AS t ([Number], [Id])"
        }
    }
}
