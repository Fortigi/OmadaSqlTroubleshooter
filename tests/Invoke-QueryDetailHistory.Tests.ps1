#Requires -Version 7.0
BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Invoke-QueryDetailHistory.ps1")

    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)]$Message, $LogType) process { } }
    function Open-SqlHistoryForm { param($DoId, $QueryName, $Owner, $QueryUId, $SelectChangeDate, $SelectChangedBy) }
    function Complete-QueryManagerChildWindow { param($Window) }
    function Update-QueryDetailForm { }
    function Get-DataGridSelectedRow { param($Grid) }
}

Describe 'Invoke-QueryDetailHistory' -Tag 'Unit' {
    BeforeEach {
        $Script:QueryDetailForm = [PSCustomObject]@{ Query = [PSCustomObject]@{ DoId = "42"; DisplayName = "Accounts"; UId = "6a0f" }; Definition = "details-window" }
        Mock Open-SqlHistoryForm { }
        Mock Complete-QueryManagerChildWindow { $false }
        Mock Update-QueryDetailForm { }
    }

    It 'Should open the history of the query, with its UId, at the newest version' {
        Invoke-QueryDetailHistory

        Should -Invoke Open-SqlHistoryForm -Times 1 -Exactly -ParameterFilter { $DoId -eq "42" -and $QueryName -eq "Accounts" -and $Owner -eq "details-window" -and $QueryUId -eq "6a0f" -and $null -eq $SelectChangeDate }
        Should -Invoke Update-QueryDetailForm -Times 1 -Exactly
    }

    It 'Should open it at the version of a History row' {
        Invoke-QueryDetailHistory -Entry ([PSCustomObject]@{ When = [datetime]"2026-01-01"; Who = "ann"; What = "Modify" })

        Should -Invoke Open-SqlHistoryForm -Times 1 -Exactly -ParameterFilter { $SelectChangeDate -eq [datetime]"2026-01-01" -and $SelectChangedBy -eq "ann" }
    }

    It 'Should not read the details again when a restore closed them' {
        Mock Complete-QueryManagerChildWindow { $true }

        Invoke-QueryDetailHistory

        Should -Invoke Update-QueryDetailForm -Times 0 -Exactly
    }
}

Describe 'Invoke-QueryDetailHistoryRow' -Tag 'Unit' {
    BeforeEach {
        $Script:QueryDetailForm = [PSCustomObject]@{ Elements = [PSCustomObject]@{ DataGridQueryHistory = "history-grid" } }
        Mock Invoke-QueryDetailHistory { }
    }

    It 'Should open the history at the row the selection is in' {
        Mock Get-DataGridSelectedRow { [PSCustomObject]@{ When = [datetime]"2026-01-01"; Who = "ann" } }

        Invoke-QueryDetailHistoryRow

        Should -Invoke Get-DataGridSelectedRow -Times 1 -Exactly -ParameterFilter { $Grid -eq "history-grid" }
        Should -Invoke Invoke-QueryDetailHistory -Times 1 -Exactly -ParameterFilter { $Entry.Who -eq "ann" }
    }

    It 'Should do nothing for a selection over <Case>' -ForEach @(@{ Case = 'no rows'; Count = 0 }, @{ Case = 'two rows'; Count = 2 }) {
        Mock Get-DataGridSelectedRow { if ($Count -gt 0) { 1..$Count | ForEach-Object { [PSCustomObject]@{ Who = $_ } } } }

        Invoke-QueryDetailHistoryRow

        Should -Invoke Invoke-QueryDetailHistory -Times 0 -Exactly
    }
}
