#Requires -Version 7.0
# Tests for the one log-level inclusion table (issue #121).
#
# The window and the session log file filter on DIFFERENT levels - the file may reasonably be more
# verbose than the window - so the "does a message of this type survive this level?" decision is no
# longer something Write-LogOutput can answer inline for one level only. It lives here, and both
# callers ask it.
#
# The table these tests assert is the one Write-LogOutput has always applied. Anything else would be
# a silent change to what the log window shows.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Test-LogLevelThreshold.ps1")

    $Script:AllLogType = @("DEBUG", "INFO", "ERROR", "VERBOSE", "WARNING", "FATAL", "LOG", "VERBOSE2")
}

Describe "Test-LogLevelThreshold" {

    Context "The table Write-LogOutput has always applied" {

        It "at <Level> includes exactly <Included>" -ForEach @(
            @{ Level = "VERBOSE2"; Included = @("DEBUG", "INFO", "ERROR", "VERBOSE", "WARNING", "FATAL", "LOG", "VERBOSE2") }
            @{ Level = "VERBOSE"; Included = @("DEBUG", "INFO", "ERROR", "VERBOSE", "WARNING", "FATAL", "LOG") }
            @{ Level = "DEBUG"; Included = @("DEBUG", "INFO", "ERROR", "WARNING", "FATAL", "LOG") }
            @{ Level = "INFO"; Included = @("INFO", "ERROR", "WARNING", "FATAL", "LOG") }
            @{ Level = "WARNING"; Included = @("ERROR", "WARNING", "FATAL", "LOG") }
            @{ Level = "ERROR"; Included = @("ERROR", "FATAL", "LOG") }
            @{ Level = "FATAL"; Included = @("ERROR", "FATAL", "LOG") }
        ) {
            foreach ($LogType in $Script:AllLogType) {
                $Expected = $Included -contains $LogType
                Test-LogLevelThreshold -Level $Level -LogType $LogType | Should -Be $Expected -Because ("{0} at level {1} should be {2}" -f $LogType, $Level, $Expected)
            }
        }
    }

    Context "Values that are not a level at all" {

        It "excludes everything at an unknown level, matching the switch's default branch" {
            foreach ($LogType in $Script:AllLogType) {
                Test-LogLevelThreshold -Level "NOSUCHLEVEL" -LogType $LogType | Should -BeFalse
            }
        }

        It "excludes everything when the level is empty" {
            Test-LogLevelThreshold -Level "" -LogType "ERROR" | Should -BeFalse
        }

        It "excludes a log type the application does not emit" {
            Test-LogLevelThreshold -Level "VERBOSE2" -LogType "TRACE" | Should -BeFalse
        }
    }

    Context "Casing" {

        It "treats a lower-case level as the level it names" {
            # A hand-edited configuration file is the realistic source of "verbose".
            Test-LogLevelThreshold -Level "verbose" -LogType "DEBUG" | Should -BeTrue
        }
    }

    Context "Both parameters are required" {

        It "declares <Parameter> mandatory" -ForEach @(
            @{ Parameter = "Level" }
            @{ Parameter = "LogType" }
        ) {
            # Asserted from the metadata rather than by calling without it: a missing mandatory
            # parameter prompts, and a prompt hangs an unattended run.
            (Get-Command Test-LogLevelThreshold).Parameters[$Parameter].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }
    }
}
