#Requires -Version 7.0
# Tests for the names and headers of session log files (issue #121, as the maintainer revised it).
#
# Pruning deletes by what these functions recognize, so the assertions that matter most are the
# rejections: a user's own file, a near miss, and the names of the design that never shipped must all
# fail to parse. The header tests pin the one line that reaches disk without the redaction gate to
# three typed values.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Get-SessionLogFileName.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:StartTime = [datetime]::new(2026, 9, 14, 8, 5, 3)
}

Describe "Get-SessionLogFileName" {

    Context "The names" {

        It "gives the part being written a fixed name" {
            Get-SessionLogFileName | Should -BeExactly "OmadaSqlTroubleshooter.log"
        }

        It "names a part for its session and a zero-padded part number" {
            Get-SessionLogFileName -SessionKey "20260914-080503" -Part 1 | Should -BeExactly "OmadaSqlTroubleshooter_20260914-080503_001.log"
            Get-SessionLogFileName -SessionKey "20260914-080503b" -Part 42 | Should -BeExactly "OmadaSqlTroubleshooter_20260914-080503b_042.log"
        }

        It "refuses a session key it did not build" {
            { Get-SessionLogFileName -SessionKey "my-notes" -Part 1 } | Should -Throw
        }

        It "refuses part <Part>, which three digits cannot carry" -ForEach @(
            @{ Part = 0 }
            @{ Part = 1000 }
        ) {
            { Get-SessionLogFileName -SessionKey "20260914-080503" -Part $Part } | Should -Throw
        }
    }

    Context "Session keys" {

        It "is the start time as yyyyMMdd-HHmmss" {
            New-SessionLogFileSessionKey -StartTime $Script:StartTime | Should -BeExactly "20260914-080503"
        }

        It "adds a letter from b to z when that second is already taken" {
            New-SessionLogFileSessionKey -StartTime $Script:StartTime -Index 1 | Should -BeExactly "20260914-080503b"
            New-SessionLogFileSessionKey -StartTime $Script:StartTime -Index 25 | Should -BeExactly "20260914-080503z"
        }

        It "sorts ordinally by start time, then same-second letter, then part" {
            $Expected = @(
                "OmadaSqlTroubleshooter_20260914-080503_001.log"
                "OmadaSqlTroubleshooter_20260914-080503_002.log"
                "OmadaSqlTroubleshooter_20260914-080503_010.log"
                "OmadaSqlTroubleshooter_20260914-080503b_001.log"
                "OmadaSqlTroubleshooter_20260914-080504_001.log"
            )
            $Sorted = [System.Collections.Generic.List[string]]::new([string[]]@($Expected[4], $Expected[2], $Expected[0], $Expected[3], $Expected[1]))

            $Sorted.Sort([System.StringComparer]::Ordinal)

            ($Sorted -join ",") | Should -BeExactly ($Expected -join ",")
        }
    }

    Context "Recognizing the application's own files, and only those" {

        It "recognizes <Name>" -ForEach @(
            @{ Name = "OmadaSqlTroubleshooter.log" }
            @{ Name = "OmadaSqlTroubleshooter_20260914-080503_001.log" }
            @{ Name = "OmadaSqlTroubleshooter_20260914-080503b_999.log" }
        ) {
            ConvertFrom-SessionLogFileName -Name $Name | Should -Not -BeNullOrEmpty
        }

        It "rejects <Name>" -ForEach @(
            @{ Name = "my-own-notes.log" }
            @{ Name = "OmadaSqlTroubleshooter_backup.log" }
            @{ Name = "OmadaSqlTroubleshooter.log.bak" }
            @{ Name = "omadasqltroubleshooter.log" }
            @{ Name = "OmadaSqlTroubleshooter_20260914-080503_pid4242_001.log" }
            @{ Name = "OmadaSqlTroubleshooter_20260914-080503_000.log" }
            @{ Name = "OmadaSqlTroubleshooter_20260914-080503_1000.log" }
            @{ Name = "OmadaSqlTroubleshooter_20260914-080503a_001.log" }
            @{ Name = "OmadaSqlTroubleshooter_20261399-250000_001.log" }
        ) {
            ConvertFrom-SessionLogFileName -Name $Name | Should -BeNullOrEmpty
        }

        It "reads the session and the part back out of a part's name" {
            $Parsed = ConvertFrom-SessionLogFileName -Name "OmadaSqlTroubleshooter_20260914-080503b_007.log"

            $Parsed.IsActive | Should -BeFalse
            $Parsed.SessionKey | Should -BeExactly "20260914-080503b"
            $Parsed.Part | Should -Be 7
        }

        It "produces only names the file system pre-filter lets through" {
            Get-SessionLogFileName | Should -BeLike (Get-SessionLogFilePattern)
            Get-SessionLogFileName -SessionKey "20260914-080503" -Part 3 | Should -BeLike (Get-SessionLogFilePattern)
        }
    }

    Context "The header" {

        BeforeEach {
            $Script:Folder = Join-Path ([System.IO.Path]::GetTempPath()) -ChildPath ("OmadaSqlLogName_{0}" -f ([guid]::NewGuid().ToString("N")))
            [System.IO.Directory]::CreateDirectory($Script:Folder) | Out-Null
        }

        AfterEach {
            Remove-Item -LiteralPath $Script:Folder -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "records the session key, the start time and the process" {
            $Header = Get-SessionLogFileHeader -SessionKey "20260914-080503" -StartTime $Script:StartTime -ProcessId 4242

            $Header | Should -Match "^OmadaSqlTroubleshooter session log; session 20260914-080503; started 2026-09-14T08:05:03"
            $Header | Should -Match "; process 4242$"
        }

        It "is read back from the first line of a file" {
            $Path = Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter.log"
            [System.IO.File]::WriteAllText($Path, ("{0}`r`nline one`r`n" -f (Get-SessionLogFileHeader -SessionKey "20260914-080503b" -StartTime $Script:StartTime -ProcessId 4242)))

            (Read-SessionLogFileHeader -Path $Path).SessionKey | Should -BeExactly "20260914-080503b"
        }

        It "reads nothing from a file without a header" {
            $Path = Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter.log"
            [System.IO.File]::WriteAllText($Path, "just a line`r`n")

            Read-SessionLogFileHeader -Path $Path | Should -BeNullOrEmpty
        }

        It "reads nothing, and throws nothing, for a file that does not exist" {
            Read-SessionLogFileHeader -Path (Join-Path $Script:Folder -ChildPath "missing.log") | Should -BeNullOrEmpty
        }

        It "has no parameter a log message could arrive through" {
            # The header is written without passing through Protect-LogMessage. That is only safe
            # while it can carry nothing but a validated key, a date and a number.
            $Command = Get-Command Get-SessionLogFileHeader
            $CommonParameter = [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            $ParameterName = @($Command.Parameters.Keys | Where-Object { $_ -notin $CommonParameter } | Sort-Object)

            $ParameterName | Should -Be @("ProcessId", "SessionKey", "StartTime")
            $Command.Parameters["StartTime"].ParameterType | Should -Be ([datetime])
            $Command.Parameters["ProcessId"].ParameterType | Should -Be ([int])
            @($Command.Parameters["SessionKey"].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidatePatternAttribute] }).Count | Should -Be 1
            { Get-SessionLogFileHeader -SessionKey "password=hunter2" -StartTime $Script:StartTime -ProcessId 1 } | Should -Throw
        }
    }

    Context "Choosing a part number" {

        It "skips a number whose file already exists, so nothing is overwritten" {
            $Folder = Join-Path ([System.IO.Path]::GetTempPath()) -ChildPath ("OmadaSqlLogName_{0}" -f ([guid]::NewGuid().ToString("N")))
            [System.IO.Directory]::CreateDirectory($Folder) | Out-Null
            try {
                [System.IO.File]::WriteAllText((Join-Path $Folder -ChildPath "OmadaSqlTroubleshooter_20260914-080503_001.log"), "taken")

                $Available = Get-AvailableSessionLogFilePart -Directory $Folder -SessionKey "20260914-080503" -Part 1

                $Available.Part | Should -Be 2
                (Split-Path $Available.Path -Leaf) | Should -BeExactly "OmadaSqlTroubleshooter_20260914-080503_002.log"
            }
            finally {
                Remove-Item -LiteralPath $Folder -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Required parameters" {

        It "declares <Parameter> of <Command> mandatory" -ForEach @(
            @{ Command = "Get-SessionLogFileHeader"; Parameter = "SessionKey" }
            @{ Command = "Get-SessionLogFileHeader"; Parameter = "StartTime" }
            @{ Command = "Get-SessionLogFileHeader"; Parameter = "ProcessId" }
            @{ Command = "New-SessionLogFileSessionKey"; Parameter = "StartTime" }
        ) {
            # Asserted from the metadata: calling without a mandatory parameter prompts, and a
            # prompt hangs an unattended run.
            (Get-Command $Command).Parameters[$Parameter].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }
    }
}
