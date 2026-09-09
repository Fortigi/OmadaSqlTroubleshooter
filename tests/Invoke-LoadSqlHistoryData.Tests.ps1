#Requires -Version 7.0
# Issue #96, from a live session:
#
#   Invoke-LoadSqlHistoryData (25): You cannot call a method on a null-valued expression.
#
# This runs from the history form's Loaded handler, and Get-SqlHistory BLOCKS for a full round-trip -
# so the window is on screen and interactive for the whole fetch. Changing the selected query closes
# it, and so does the user. The existing guard covered the DATA; nothing covered the FORM.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Write-ContainedErrorLog.ps1")
    . (Join-Path $PrivatePath -ChildPath "Invoke-LoadSqlHistoryData.ps1")

    $script:LogMessages = [System.Collections.Generic.List[object]]::new()
    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
        process { $script:LogMessages.Add([pscustomobject]@{ LogType = $LogType; Message = [string]$InputObject }) }
    }

    function script:New-GridStub {
        return [pscustomobject]@{ ItemsSource = $null; SelectedIndex = -1 }
    }

    function script:Initialize-HistoryState {
        param([switch]$WindowClosed, [switch]$NoElements)

        $script:LogMessages.Clear()

        if ($WindowClosed) {
            $Script:SqlHistoryForm = $null
        }
        elseif ($NoElements) {
            $Script:SqlHistoryForm = [pscustomobject]@{ Elements = $null }
        }
        else {
            $Script:SqlHistoryForm = [pscustomobject]@{ Elements = [pscustomobject]@{ DataGridHistory = (New-GridStub) } }
        }
    }

    # A script-scoped variable rather than a Mock closing over a parameter: the mock scriptblock
    # runs later, in a scope where that parameter no longer exists, so it would always answer null.
    function script:Set-History {
        param($Rows)
        $script:HistoryRows = $Rows
    }

    function script:New-Row {
        param([string]$Name = "x", $ChangeDate = ([DateTime]::new(2026, 8, 25)))
        return [pscustomobject]@{ SqlObjectName = $Name; ChangeDate = $ChangeDate }
    }

    function Get-SqlHistory { return $script:HistoryRows }
}

Describe "Invoke-LoadSqlHistoryData" {
    Context "The window is still open" {
        BeforeEach { Initialize-HistoryState }

        It "binds the rows to the grid" {
            Set-History -Rows @((New-Row -Name "a"), (New-Row -Name "b"))

            Invoke-LoadSqlHistoryData

            @($Script:SqlHistoryForm.Elements.DataGridHistory.ItemsSource).Count | Should -Be 2
        }

        It "selects the first row" {
            Set-History -Rows @((New-Row -Name "a"))

            Invoke-LoadSqlHistoryData

            $Script:SqlHistoryForm.Elements.DataGridHistory.SelectedIndex | Should -Be 0
        }

        It "sorts newest first" {
            Set-History -Rows @(
                (New-Row -Name "old" -ChangeDate ([DateTime]::new(2026, 1, 1))),
                (New-Row -Name "new" -ChangeDate ([DateTime]::new(2026, 8, 25)))
            )

            Invoke-LoadSqlHistoryData

            @($Script:SqlHistoryForm.Elements.DataGridHistory.ItemsSource)[0].SqlObjectName | Should -Be "new"
        }

        It "copes with a row whose date could not be read" {
            # ConvertTo-OmadaHistoryDate returns null for an unreadable date (issue #95), so Sort-Object
            # has to handle nulls - the two fixes meet here.
            Set-History -Rows @((New-Row -Name "dated"), (New-Row -Name "undated" -ChangeDate $null))

            { Invoke-LoadSqlHistoryData } | Should -Not -Throw
            @($Script:SqlHistoryForm.Elements.DataGridHistory.ItemsSource).Count | Should -Be 2
        }
    }

    Context "The window closed while the fetch was running" {
        It "does not throw when the form has gone" {
            Initialize-HistoryState -WindowClosed
            Set-History -Rows @((New-Row))

            { Invoke-LoadSqlHistoryData } | Should -Not -Throw
        }

        It "does not throw when the form is there but its elements are not" {
            Initialize-HistoryState -NoElements
            Set-History -Rows @((New-Row))

            { Invoke-LoadSqlHistoryData } | Should -Not -Throw
        }

        It "says nothing above DEBUG - the user closed a window and has moved on" {
            Initialize-HistoryState -WindowClosed
            Set-History -Rows @((New-Row))

            Invoke-LoadSqlHistoryData

            @($script:LogMessages | Where-Object { $_.LogType -ne "DEBUG" }).Count | Should -Be 0
        }

        It "records why it stopped" {
            Initialize-HistoryState -WindowClosed
            Set-History -Rows @((New-Row))

            Invoke-LoadSqlHistoryData

            ($script:LogMessages.Message -join " ") | Should -Match "closed while its data was loading"
        }
    }

    Context "There is no history to show" {
        BeforeEach { Initialize-HistoryState }

        It "returns quietly for an empty result" {
            Set-History -Rows @()

            { Invoke-LoadSqlHistoryData } | Should -Not -Throw
            $Script:SqlHistoryForm.Elements.DataGridHistory.ItemsSource | Should -BeNullOrEmpty
        }

        It "returns quietly for a null result" {
            # Get-SqlHistory returns null on failure - including the date failure of #95 before it
            # was fixed.
            Set-History -Rows $null

            { Invoke-LoadSqlHistoryData } | Should -Not -Throw
        }
    }
}
