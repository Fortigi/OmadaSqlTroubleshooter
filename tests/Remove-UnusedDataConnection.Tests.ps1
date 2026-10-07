#Requires -Version 7.0
# Issue #165. The filter that reduces the data connection dropdown to the databases actually in use.
#
# Get-DataConnectionReferenceList is loaded for real, not stubbed: this function's whole correctness
# rests on where a name ends, and that parser is what decides it. A stub would let the two drift, which
# is precisely the failure mode - a filter that matches a name the rest of the application splits
# differently.
#
# The three-state flag is the other half. "Not known" must behave like "off", and neither may remove
# anything, because hiding a database the user needs is worse than offering one that does not work -
# which is what the application did before this feature anyway.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Resolve-DataConnectionReference.ps1")
    . (Join-Path $PrivatePath -ChildPath "Remove-UnusedDataConnection.ps1")

    $script:LogMessages = [System.Collections.Generic.List[object]]::new()
    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { $script:LogMessages.Add([pscustomobject]@{ LogType = $LogType; Message = [string]$InputObject }) }
    }

    $Script:FullList = @(
        "OISES - 1001572"
        "ODW - 2003044"
        "ODWMD - 2003045"
        "Source System Data DB - 2003046"
        "ODWS - 2003047"
        "Reporting - 1001999"
    )
}

Describe "Remove-UnusedDataConnection - when ingestion is enabled" {

    # Inside the Describe, never at the root: Pester 6 rejects a root-level BeforeEach outright with
    # "Each test setup is not supported in root (directly in the block container)", and it fails the
    # whole container rather than one test - so every assertion in the file is reported as failed.
    BeforeEach {
        $script:LogMessages.Clear()
    }

    It "removes the three unused ODW connections" {
        $Private:Kept = Remove-UnusedDataConnection -OptionList $Script:FullList -IngestionEnabled $true

        $Private:Kept | Should -Be @("OISES - 1001572", "ODW - 2003044", "Reporting - 1001999")
    }

    It "keeps ODW itself, which is where the flag was read from" {
        $Private:Kept = Remove-UnusedDataConnection -OptionList $Script:FullList -IngestionEnabled $true

        $Private:Kept | Should -Contain "ODW - 2003044"
    }

    It "preserves the dropdown's order" {
        # The order is the one Update-DataConnectionList sorted into, and the schema window shows its
        # database nodes in the same order.
        $Private:Kept = Remove-UnusedDataConnection -OptionList @("Reporting - 1001999", "ODWS - 2003047", "OISES - 1001572") -IngestionEnabled $true

        $Private:Kept | Should -Be @("Reporting - 1001999", "OISES - 1001572")
    }

    It "matches the name case-insensitively, because the tenant's casing is not the user's choice" {
        $Private:Kept = Remove-UnusedDataConnection -OptionList @("odwmd - 2003045", "OISES - 1001572") -IngestionEnabled $true

        $Private:Kept | Should -Be @("OISES - 1001572")
    }

    It "matches a name with surrounding whitespace" {
        $Private:Kept = Remove-UnusedDataConnection -OptionList @("  ODWS   - 2003047", "OISES - 1001572") -IngestionEnabled $true

        $Private:Kept | Should -Be @("OISES - 1001572")
    }

    It "logs what it removed, at DEBUG and nowhere else" {
        # Nothing user-visible: a notice would raise a question for every user on every connect about
        # behaviour that is correct.
        Remove-UnusedDataConnection -OptionList $Script:FullList -IngestionEnabled $true | Out-Null

        $Private:Logged = @($script:LogMessages | Where-Object { $_.Message -like "*filtered unused data connection*" })
        @($Private:Logged).Count | Should -Be 1
        $Private:Logged[0].LogType | Should -Be "DEBUG"
        $Private:Logged[0].Message | Should -Match "ODWMD"
        $Private:Logged[0].Message | Should -Match "Source System Data DB"
        $Private:Logged[0].Message | Should -Match "ODWS"
    }

    It "says nothing when there was nothing to remove" {
        Remove-UnusedDataConnection -OptionList @("OISES - 1001572") -IngestionEnabled $true | Out-Null

        @($script:LogMessages | Where-Object { $_.Message -like "*filtered unused*" }).Count | Should -Be 0
    }
}

Describe "Remove-UnusedDataConnection - never a substring match" {
    # The trade-off stated in the function: an exact match can miss a renamed "ODWS (archive)", and
    # that is accepted. What is NOT acceptable is hiding a connection whose name merely contains one of
    # the three.

    It "keeps a connection whose name only starts with a filtered one" {
        $Private:Kept = Remove-UnusedDataConnection -OptionList @("ODWS Reporting - 2003099", "OISES - 1001572") -IngestionEnabled $true

        $Private:Kept | Should -Contain "ODWS Reporting - 2003099"
    }

    It "keeps a connection whose name contains a filtered one" {
        $Private:Kept = Remove-UnusedDataConnection -OptionList @("Legacy ODWMD copy - 2003098") -IngestionEnabled $true

        $Private:Kept | Should -Be @("Legacy ODWMD copy - 2003098")
    }

    It "keeps a renamed one, which is the accepted cost of an exact match" {
        # Documented as the deliberate failure: the user then sees a database that does not work, which
        # is what they saw before this feature existed.
        $Private:Kept = Remove-UnusedDataConnection -OptionList @("ODWS (archive) - 2003097") -IngestionEnabled $true

        $Private:Kept | Should -Be @("ODWS (archive) - 2003097")
    }

    It "splits a name containing ' - ' from the right, as the rest of the application does" {
        # "Reporting - archive" is a legitimate name. Splitting from the left would make its name
        # "Reporting", and a filter that disagreed with Get-DataConnectionReferenceList about where a
        # name ends is the drift this suite exists to prevent.
        $Private:Kept = Remove-UnusedDataConnection -OptionList @("Reporting - archive - 1001999", "ODWS - 2003047") -IngestionEnabled $true

        $Private:Kept | Should -Be @("Reporting - archive - 1001999")
    }
}

Describe "Remove-UnusedDataConnection - when the flag is not an explicit true" {

    BeforeEach {
        $script:LogMessages.Clear()
    }

    It "leaves the list untouched when ingestion is disabled" {
        $Private:Kept = Remove-UnusedDataConnection -OptionList $Script:FullList -IngestionEnabled $false

        $Private:Kept | Should -Be $Script:FullList
    }

    It "leaves the list untouched when the flag is not known" {
        # Absent from the page, unparseable, or the probe failed. All arrive as $null, and none of them
        # is permission to hide a database.
        $Private:Kept = Remove-UnusedDataConnection -OptionList $Script:FullList -IngestionEnabled $null

        $Private:Kept | Should -Be $Script:FullList
    }

    It "leaves the list untouched when the parameter is omitted entirely" {
        $Private:Kept = Remove-UnusedDataConnection -OptionList $Script:FullList

        $Private:Kept | Should -Be $Script:FullList
    }

    It "logs nothing, because nothing was filtered" {
        Remove-UnusedDataConnection -OptionList $Script:FullList -IngestionEnabled $null | Out-Null

        @($script:LogMessages | Where-Object { $_.Message -like "*filtered unused*" }).Count | Should -Be 0
    }
}

Describe "Remove-UnusedDataConnection - lists it cannot act on" {

    It "returns an empty array for an empty list" {
        $Private:Kept = Remove-UnusedDataConnection -OptionList @() -IngestionEnabled $true

        @($Private:Kept).Count | Should -Be 0
    }

    It "returns an empty array for null" {
        $Private:Kept = Remove-UnusedDataConnection -OptionList $null -IngestionEnabled $true

        @($Private:Kept).Count | Should -Be 0
    }

    It "drops blank entries rather than carrying them through" {
        $Private:Kept = Remove-UnusedDataConnection -OptionList @("OISES - 1001572", "", "   ") -IngestionEnabled $true

        $Private:Kept | Should -Be @("OISES - 1001572")
    }

    It "keeps an entry the reference parser cannot read" {
        # An entry in an unexpected shape is not a connection this feature knows anything about, and
        # dropping it would hide a connection for a reason unrelated to ingestion.
        $Private:Kept = Remove-UnusedDataConnection -OptionList @("NoDoIdHere", "ODWS - 2003047") -IngestionEnabled $true

        $Private:Kept | Should -Contain "NoDoIdHere"
        $Private:Kept | Should -Not -Contain "ODWS - 2003047"
    }
}
