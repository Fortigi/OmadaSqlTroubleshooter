#Requires -Version 7.0
# Issue #95. From a live session on an nl-NL machine:
#
#   Get-SqlHistory (88): Cannot bind parameter 'Date'. Cannot convert value "8/25/2026 12:03 PM"
#   to type "System.DateTime". Error: "String '8/25/2026 12:03 PM' was not recognized as a valid
#   DateTime."
#
# "When" is a display string the SERVER formatted, not ISO 8601, so its format follows a locale -
# and Get-Date binds to a [DateTime] parameter, which converts under the CURRENT culture. Day 8 of
# month 25 is not a date.
#
# The tests run under an explicitly non-US culture. On a US build agent the original defect is
# invisible, so a test that inherits the ambient culture would pass on CI and fail on the machine
# that reported it.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "ConvertTo-OmadaHistoryDate.ps1")

    $script:LogMessages = [System.Collections.Generic.List[object]]::new()
    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
        process { $script:LogMessages.Add([pscustomobject]@{ LogType = $LogType; Message = [string]$InputObject }) }
    }

    # Runs a scriptblock under a chosen culture and restores the original afterwards.
    function script:Use-Culture {
        param([string]$Name, [scriptblock]$Body)

        $Private:Previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Name)
            return (& $Body)
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $Private:Previous
        }
    }
}

Describe "ConvertTo-OmadaHistoryDate" {
    BeforeEach { $script:LogMessages.Clear() }

    It "reads the value that broke history on nl-NL" {
        # The reported case, under the reporting machine's culture.
        $Private:Result = Use-Culture -Name "nl-NL" -Body { ConvertTo-OmadaHistoryDate -Value "8/25/2026 12:03 PM" }

        $Private:Result | Should -Not -BeNullOrEmpty
        $Private:Result.Year | Should -Be 2026
        $Private:Result.Month | Should -Be 8
        $Private:Result.Day | Should -Be 25
        $Private:Result.Hour | Should -Be 12
    }

    It "confirms the premise: Get-Date really does fail on that value under nl-NL" {
        # Asserted so this suite cannot quietly stop testing the actual defect - if the platform ever
        # started accepting it, these tests would be proving nothing.
        Use-Culture -Name "nl-NL" -Body {
            { Get-Date "8/25/2026 12:03 PM" -ErrorAction Stop } | Should -Throw
        }
    }

    It "still reads a value rendered the local way" {
        # The other half, and the reason a single culture is not enough: fixing the reported case
        # with InvariantCulture alone would trade one locale's failure for another's.
        $Private:Result = Use-Culture -Name "nl-NL" -Body { ConvertTo-OmadaHistoryDate -Value "25-08-2026 12:03" }

        $Private:Result | Should -Not -BeNullOrEmpty
        $Private:Result.Month | Should -Be 8
        $Private:Result.Day | Should -Be 25
    }

    It "reads an ISO 8601 value, should the endpoint ever return one" {
        $Private:Result = Use-Culture -Name "nl-NL" -Body { ConvertTo-OmadaHistoryDate -Value "2026-08-25T12:03:00" }

        $Private:Result.Month | Should -Be 8
        $Private:Result.Day | Should -Be 25
    }

    It "works the same on a US machine, where the defect was invisible" {
        $Private:Result = Use-Culture -Name "en-US" -Body { ConvertTo-OmadaHistoryDate -Value "8/25/2026 12:03 PM" }

        $Private:Result.Month | Should -Be 8
        $Private:Result.Day | Should -Be 25
    }

    Context "What it does with something it cannot read" {
        It "returns null rather than throwing" {
            # The actual severity of #95: the throw propagated out of the row loop to the function's
            # outer catch, so ONE unreadable timestamp cost the user the entire history list.
            $Private:Result = $null
            { $script:Unreadable = ConvertTo-OmadaHistoryDate -Value "not a date at all" } | Should -Not -Throw
            $script:Unreadable | Should -BeNullOrEmpty
        }

        It "records it at DEBUG, not as an error" {
            ConvertTo-OmadaHistoryDate -Value "not a date at all" | Out-Null

            @($script:LogMessages | Where-Object { $_.LogType -ne "DEBUG" }).Count | Should -Be 0
        }

        It "names the culture it tried, so the log explains itself" {
            ConvertTo-OmadaHistoryDate -Value "not a date at all" | Out-Null

            $script:LogMessages[0].Message | Should -Match "current culture"
        }

        It "returns null for null and for empty" {
            ConvertTo-OmadaHistoryDate -Value $null | Should -BeNullOrEmpty
            ConvertTo-OmadaHistoryDate -Value "" | Should -BeNullOrEmpty
            ConvertTo-OmadaHistoryDate -Value "   " | Should -BeNullOrEmpty
        }
    }

    It "passes a real DateTime straight through" {
        # No round trip through a culture for a value that never needed parsing.
        $Private:Now = [DateTime]::new(2026, 8, 25, 12, 3, 0)

        ConvertTo-OmadaHistoryDate -Value $Private:Now | Should -Be $Private:Now
    }
}

Describe "Get-SqlHistory uses it" {
    It "no longer converts the change date with Get-Date" {
        # Get-Date binds to a [DateTime] parameter, which is what made the conversion culture-
        # sensitive in the first place.
        $Private:Source = Get-Content -Path (Join-Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "src\Lib\Functions\Private") "Get-SqlHistory.ps1") -Raw

        $Private:Source | Should -Not -Match 'ChangeDate\s*=\s*\(Get-Date'
        $Private:Source | Should -Match 'ChangeDate\s*=\s*ConvertTo-OmadaHistoryDate'
    }
}
