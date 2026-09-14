#Requires -Version 7.0
# Tests for the session log file's name (issue #121).
#
# The name carries the two things that make one session's file findable among all the others - when
# it started and which process wrote it - and a part number, because a session that reaches the size
# ceiling rolls into a second file rather than stopping.
#
# The assertion that matters most is the last one: pruning finds files by a wildcard pattern and
# groups them back into sessions by a regular expression, so a name that stops matching either would
# leave the folder growing without bound while every other test still passed.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Get-SessionLogFileName.ps1")

    $Script:StartTime = [datetime]::new(2026, 9, 14, 8, 5, 3)
}

Describe "Get-SessionLogFileName" {

    Context "The name" {

        It "carries the start timestamp, the process id and the part" {
            Get-SessionLogFileName -StartTime $Script:StartTime -ProcessId 4242 -Part 1 |
                Should -BeExactly "OmadaSqlTroubleshooter_20260914-080503_pid4242_001.log"
        }

        It "defaults to the first part" {
            Get-SessionLogFileName -StartTime $Script:StartTime -ProcessId 4242 |
                Should -BeExactly "OmadaSqlTroubleshooter_20260914-080503_pid4242_001.log"
        }

        It "pads the part so parts of one session sort in the order they were written" {
            $Name = @(1, 2, 10) | ForEach-Object { Get-SessionLogFileName -StartTime $Script:StartTime -ProcessId 4242 -Part $_ }

            ($Name | Sort-Object) -join "," | Should -BeExactly ($Name -join ",")
        }

        It "does not collide between two instances started in the same second" {
            $First = Get-SessionLogFileName -StartTime $Script:StartTime -ProcessId 1001
            $Second = Get-SessionLogFileName -StartTime $Script:StartTime -ProcessId 1002

            $First | Should -Not -BeExactly $Second
        }
    }

    Context "Pruning has to be able to find what this writes" {

        It "matches the wildcard pattern pruning enumerates with" {
            $Name = Get-SessionLogFileName -StartTime $Script:StartTime -ProcessId 4242 -Part 7

            $Name | Should -BeLike (Get-SessionLogFilePattern)
        }

        It "matches the expression pruning groups parts back into sessions with" {
            $Name = Get-SessionLogFileName -StartTime $Script:StartTime -ProcessId 4242 -Part 7

            $Name | Should -Match (Get-SessionLogFileNameExpression)
        }

        It "groups every part of one session under the same session key" {
            $Expression = Get-SessionLogFileNameExpression
            $Key = @(1, 2, 3) | ForEach-Object {
                $Name = Get-SessionLogFileName -StartTime $Script:StartTime -ProcessId 4242 -Part $_
                if ($Name -match $Expression) { $Matches["Session"] }
            }

            ($Key | Select-Object -Unique | Measure-Object).Count | Should -Be 1
        }

        It "gives two instances started in the same second different session keys" {
            $Expression = Get-SessionLogFileNameExpression
            $Key = @(1001, 1002) | ForEach-Object {
                $Name = Get-SessionLogFileName -StartTime $Script:StartTime -ProcessId $_
                if ($Name -match $Expression) { $Matches["Session"] }
            }

            ($Key | Select-Object -Unique | Measure-Object).Count | Should -Be 2
        }

        It "does not match a file the application did not write" {
            "notes.log" | Should -Not -Match (Get-SessionLogFileNameExpression)
            "OmadaSqlTroubleshooter.log" | Should -Not -Match (Get-SessionLogFileNameExpression)
        }
    }

    Context "Required parameters" {

        It "declares <Parameter> mandatory" -ForEach @(
            @{ Parameter = "StartTime" }
            @{ Parameter = "ProcessId" }
        ) {
            # Asserted from the metadata: calling without a mandatory parameter prompts, and a
            # prompt hangs an unattended run.
            (Get-Command Get-SessionLogFileName).Parameters[$Parameter].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }
    }
}
