#Requires -Version 7.0
# Direct tests for Test-SessionLogFileSessionKey (issue #143): the shape, case-sensitively, and a
# real date in it - pruning deletes by this answer, so it must not accept anything looser.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Get-SessionLogFileName.ps1")
}

Describe "Test-SessionLogFileSessionKey" -Tag "Unit" {

    Context "A well-formed key" {

        It "accepts a plain key with no letter suffix" {
            Test-SessionLogFileSessionKey -SessionKey "20260914-080503" | Should -BeTrue
        }

        It "accepts a key with a letter suffix from a second collision" {
            Test-SessionLogFileSessionKey -SessionKey "20260914-080503b" | Should -BeTrue
        }
    }

    Context "A malformed key" {

        It "rejects <SessionKey>" -ForEach @(
            @{ SessionKey = "2026091-080503" }
            @{ SessionKey = "20260914-08050" }
            @{ SessionKey = "20260914_080503" }
            @{ SessionKey = "20260914-080503a" }
            @{ SessionKey = "20260914-080503B" }
            @{ SessionKey = "20260914-080503bb" }
            @{ SessionKey = "not a key at all" }
        ) {
            Test-SessionLogFileSessionKey -SessionKey $SessionKey | Should -BeFalse
        }

        It "rejects a key whose shape is right but whose date is not real" {
            Test-SessionLogFileSessionKey -SessionKey "20261301-080503" | Should -BeFalse
        }

        It "rejects a key whose shape is right but whose time is not real" {
            Test-SessionLogFileSessionKey -SessionKey "20260914-256199" | Should -BeFalse
        }
    }

    Context "Absent input" {

        It "rejects an empty string" {
            Test-SessionLogFileSessionKey -SessionKey "" | Should -BeFalse
        }

        It "rejects null" {
            Test-SessionLogFileSessionKey -SessionKey $null | Should -BeFalse
        }
    }
}
