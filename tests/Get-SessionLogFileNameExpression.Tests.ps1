#Requires -Version 7.0
# Direct tests for Get-SessionLogFileNameExpression (issue #143): the expression that matches
# exactly the names Get-SessionLogFileName produces, and nothing else.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Get-SessionLogFileName.ps1")
}

Describe "Get-SessionLogFileNameExpression" -Tag "Unit" {

    Context "Names this application writes" {

        It "matches the active file name" {
            "OmadaSqlTroubleshooter.log" -cmatch (Get-SessionLogFileNameExpression) | Should -BeTrue
        }

        It "matches a numbered part and captures the session and part" {
            $Matched = "OmadaSqlTroubleshooter_20260914-080503_001.log" -cmatch (Get-SessionLogFileNameExpression)

            $Matched | Should -BeTrue
            $Matches["Session"] | Should -BeExactly "20260914-080503"
            $Matches["Part"] | Should -BeExactly "001"
        }

        It "matches a numbered part whose session has a letter suffix" {
            "OmadaSqlTroubleshooter_20260914-080503b_002.log" -cmatch (Get-SessionLogFileNameExpression) | Should -BeTrue
        }
    }

    Context "Names this application does not write" {

        It "rejects <Name>" -ForEach @(
            @{ Name = "OmadaSqlTroubleshooter_backup.log" }
            @{ Name = "OmadaSqlTroubleshooter_20260914-080503_pid4242_001.log" }
            @{ Name = "OmadaSqlTroubleshooter_20260914-080503_1.log" }
            @{ Name = "SomeOtherApp.log" }
            @{ Name = "OmadaSqlTroubleshooter.log.bak" }
            @{ Name = "OmadaSqlTroubleshooter_20260914-080503_001.LOG" }
        ) {
            $Name -cmatch (Get-SessionLogFileNameExpression) | Should -BeFalse
        }
    }
}
