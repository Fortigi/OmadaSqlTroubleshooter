#Requires -Version 7.0
BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Export-SqlHistorySelection.ps1")

    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)]$Message, $LogType) process { $script:Log += , [PSCustomObject]@{ Message = $Message; LogType = $LogType } } }
    function Get-SqlHistorySelectedItem { }
    function Invoke-SavedQueryRequest { param($Request) }
    function New-QueryManagerRequest { param($Kind, $Context) @{ Kind = $Kind; DoId = $Context.QueryDoId } }

    $script:Version = [PSCustomObject]@{
        DoId = "42"; SqlObjectName = "Accounts: open / closed"; ChangedBy = "ann"; ChangeDate = [datetime]::new(2026, 11, 26, 9, 5, 7)
        OldValue = "SELECT 1`r`nFROM a`r`nWHERE x"; NewValue = "SELECT 1`r`nFROM b"
    }
}

Describe 'Get-SqlHistoryExportFileName' -Tag 'Unit' {
    It 'Should give SQL_History_<name>_<date>_<kind> for <Kind>' -ForEach @(
        @{ Kind = "Query"; Expected = "SQL_History_Accounts_2026-01-02_query" }
        @{ Kind = "Diff"; Expected = "SQL_History_Accounts_2026-01-02_diff" }
        @{ Kind = "All"; Expected = "SQL_History_Accounts_2026-01-02_all" }
    ) {
        (Get-SqlHistoryExportFileName -QueryName "Accounts" -ChangeDate ([datetime]::new(2026, 1, 2, 3, 4, 5)) -Kind $Kind) -replace "20260102_030405", "2026-01-02" | Should -BeExactly $Expected
    }

    It 'Should write the change date as yyyyMMdd_HHmmss' {
        Get-SqlHistoryExportFileName -QueryName "A" -ChangeDate ([datetime]::new(2026, 11, 26, 9, 5, 7)) -Kind Query | Should -BeExactly "SQL_History_A_20261126_090507_query"
    }

    It 'Should make a name a file name can hold' {
        Get-SqlHistoryExportFileName -QueryName "  Accounts: open / closed?  " -ChangeDate ([datetime]::new(2026, 1, 1)) -Kind Diff | Should -BeExactly "SQL_History_Accounts_open_closed_20260101_000000_diff"
    }

    It 'Should say so when the date or the name is unknown' {
        Get-SqlHistoryExportFileName -QueryName "" -ChangeDate $null -Kind All | Should -BeExactly "SQL_History_query_unknown-date_all"
    }
}

Describe 'ConvertTo-HistoryDiffText' -Tag 'Unit' {
    It 'Should write the Diff View''s line-by-line comparison' {
        $Text = ConvertTo-HistoryDiffText -OldValue $script:Version.OldValue -NewValue $script:Version.NewValue -QueryName "Accounts" -ChangeDate $script:Version.ChangeDate

        $Text -split "\r?\n" | Should -Be @(
            "--- Accounts (before the change of 2026-11-26 09:05:07)"
            "+++ Accounts (2026-11-26 09:05:07)"
            "  SELECT 1"
            "- FROM a"
            "+ FROM b"
            "- WHERE x"
            ""
        )
    }

    It 'Should mark every line added for a first version' {
        $Lines = (ConvertTo-HistoryDiffText -OldValue $null -NewValue "SELECT 1`nFROM a" -QueryName "Q" -ChangeDate $null) -split "\r?\n"

        $Lines[0] | Should -BeExactly "--- Q (before the change of (unknown date))"
        $Lines[2..3] | Should -Be @("+ SELECT 1", "+ FROM a")
    }

    It 'Should compare case-sensitively' {
        ((ConvertTo-HistoryDiffText -OldValue "select" -NewValue "SELECT") -split "\r?\n")[2..3] | Should -Be @("- select", "+ SELECT")
    }
}

Describe 'Export-SqlHistorySelection' -Tag 'Unit' {
    BeforeEach {
        $script:Log = @()
        Mock Get-SqlHistorySelectedItem { $script:Version }
        Mock Request-SqlHistoryExportPath { Join-Path $TestDrive ("{0}{1}" -f $FileName, $Extension) }
    }

    It 'Should save the selected version''s new SQL under its file name' {
        $Path = Export-SqlHistorySelection -Kind Query

        $Path | Should -Be (Join-Path $TestDrive "SQL_History_Accounts_open_closed_20261126_090507_query.sql")
        Get-Content -Path $Path -Raw | Should -BeExactly $script:Version.NewValue
        Should -Invoke Request-SqlHistoryExportPath -Times 1 -Exactly -ParameterFilter { $Filter -like "SQL files*" -and $Title -eq "Export selected query" }
    }

    It 'Should save the selected version''s diff under its file name' {
        $Path = Export-SqlHistorySelection -Kind Diff

        $Path | Should -BeLike "*SQL_History_Accounts_open_closed_20261126_090507_diff.diff"
        Get-Content -Path $Path -Raw | Should -Match "(?m)^\+ FROM b$"
    }

    It 'Should write nothing when the dialog is cancelled' {
        Mock Request-SqlHistoryExportPath { $null }
        Mock Set-Content { }

        Export-SqlHistorySelection -Kind Query | Should -BeNullOrEmpty
        Should -Invoke Set-Content -Times 0 -Exactly
    }

    It 'Should ask for one version when the selection is in none or several' {
        Mock Get-SqlHistorySelectedItem { $null }

        Export-SqlHistorySelection -Kind Diff | Should -BeNullOrEmpty

        Should -Invoke Request-SqlHistoryExportPath -Times 0 -Exactly
        ($script:Log | Where-Object LogType -eq "WARNING").Message | Should -Match "Select one version"
    }
}

Describe 'Get-SqlHistoryQueryUId' -Tag 'Unit' {
    BeforeEach {
        $Script:SqlHistoryTarget = $null
        $Script:SqlHistoryQueryUIdCache = $null
        $Script:AppConfig = [PSCustomObject]@{ BaseUrl = "https://t" }
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $true; Result = [PSCustomObject]@{ UId = "uid-from-odata" } } }
    }

    It 'Should use the UId the window was opened with' {
        $Script:SqlHistoryTarget = [PSCustomObject]@{ DoId = "42"; UId = "given" }

        Get-SqlHistoryQueryUId -DoId "42" | Should -Be "given"
        Should -Invoke Invoke-SavedQueryRequest -Times 0 -Exactly
    }

    It 'Should read it from OData once, otherwise' {
        Get-SqlHistoryQueryUId -DoId "42" | Should -Be "uid-from-odata"
        Get-SqlHistoryQueryUId -DoId "42" | Should -Be "uid-from-odata"

        Should -Invoke Invoke-SavedQueryRequest -Times 1 -Exactly -ParameterFilter { $Request.Kind -eq "QueryObject" -and $Request.DoId -eq "42" }
    }

    It 'Should read it for another query, and for a target without one' {
        $Script:SqlHistoryTarget = [PSCustomObject]@{ DoId = "42"; UId = "" }
        $null = Get-SqlHistoryQueryUId -DoId "42"
        $null = Get-SqlHistoryQueryUId -DoId "43"

        Should -Invoke Invoke-SavedQueryRequest -Times 2 -Exactly
    }

    It 'Should give nothing when it cannot be read, or without an id' {
        Mock Invoke-SavedQueryRequest { [PSCustomObject]@{ Succeeded = $false } }

        Get-SqlHistoryQueryUId -DoId "42" | Should -Be ""
        Get-SqlHistoryQueryUId -DoId "" | Should -Be ""
    }
}

Describe 'Find-SqlHistoryItemIndex' -Tag 'Unit' {
    BeforeAll {
        $script:Items = @(
            [PSCustomObject]@{ ChangeDate = [datetime]"2026-02-01"; ChangedBy = "bob" }
            [PSCustomObject]@{ ChangeDate = [datetime]"2026-01-01"; ChangedBy = "ann" }
            [PSCustomObject]@{ ChangeDate = [datetime]"2026-01-01"; ChangedBy = "bob" }
        )
    }

    It 'Should find the version by date and user (<Who>)' -ForEach @(@{ Who = "ann"; Expected = 1 }, @{ Who = "bob"; Expected = 2 }) {
        Find-SqlHistoryItemIndex -Item $script:Items -ChangeDate ([datetime]"2026-01-01") -ChangedBy $Who | Should -Be $Expected
    }

    It 'Should give -1 for <Case>' -ForEach @(
        @{ Case = 'a change without a version'; When = [datetime]"2025-01-01"; Who = "ann" }
        @{ Case = 'another user'; When = [datetime]"2026-02-01"; Who = "ann" }
        @{ Case = 'no date'; When = $null; Who = "ann" }
    ) {
        Find-SqlHistoryItemIndex -Item $script:Items -ChangeDate $When -ChangedBy $Who | Should -Be -1
    }
}
