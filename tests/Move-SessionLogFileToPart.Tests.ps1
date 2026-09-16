#Requires -Version 7.0
# Direct tests for Move-SessionLogFileToPart (issue #143): renames a leftover
# OmadaSqlTroubleshooter.log to the next numbered part of its own session, and leaves it exactly
# where it is when the rename cannot happen. Real files and a real live handle, the way
# tests/Open-SessionLogFile.Tests.ps1 already does - "a live file cannot be renamed" is a statement
# about what the operating system allows, and only a second real handle can make it true or false.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Get-SessionLogFileName.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-SessionLogFile.ps1")
    . (Join-Path $PrivatePath -ChildPath "Open-SessionLogFile.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    function New-ClosedSessionLogFile {
        param(
            [string]$Path,
            [string]$SessionKey,
            [string[]]$Line = @("a line")
        )

        $StartTime = [datetime]::ParseExact($SessionKey.Substring(0, 15), "yyyyMMdd-HHmmss", [System.Globalization.CultureInfo]::InvariantCulture)
        $Opened = Open-SessionLogFileWriter -Path $Path -SessionKey $SessionKey -StartTime $StartTime -ProcessId 4242
        try {
            foreach ($Text in $Line) {
                $Opened.Writer.WriteLine($Text)
            }
        }
        finally {
            $Opened.Writer.Dispose()
        }
    }
}

Describe "Move-SessionLogFileToPart" -Tag "Unit" {

    BeforeEach {
        $Script:Folder = Join-Path ([System.IO.Path]::GetTempPath()) -ChildPath ("OmadaSqlLogMove_{0}" -f ([guid]::NewGuid().ToString("N")))
        [System.IO.Directory]::CreateDirectory($Script:Folder) | Out-Null
        $Script:ActivePath = Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter.log"
        $Script:Writers = [System.Collections.Generic.List[object]]::new()
    }

    AfterEach {
        foreach ($Writer in $Script:Writers) {
            try {
                $Writer.Dispose()
            }
            catch {}
        }

        Remove-Item -LiteralPath $Script:Folder -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "No active file to rotate" {

        It "returns nothing for an empty folder" {
            Move-SessionLogFileToPart -Directory $Script:Folder | Should -BeNullOrEmpty
        }
    }

    Context "A closed active file" {

        It "renames it to part 1 of its own session, and nothing else is lost" {
            New-ClosedSessionLogFile -Path $Script:ActivePath -SessionKey "20260913-170000" -Line @("the only part so far")
            $Expected = Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter_20260913-170000_001.log"

            $Result = Move-SessionLogFileToPart -Directory $Script:Folder

            $Result | Should -BeExactly $Expected
            Test-Path -LiteralPath $Script:ActivePath | Should -BeFalse
            Get-Content -LiteralPath $Result -Raw | Should -Match "the only part so far"
        }

        It "continues one past the highest part number already in the folder" {
            New-ClosedSessionLogFile -Path (Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter_20260913-170000_001.log") -SessionKey "20260913-170000"
            New-ClosedSessionLogFile -Path (Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter_20260913-170000_002.log") -SessionKey "20260913-170000"
            New-ClosedSessionLogFile -Path $Script:ActivePath -SessionKey "20260913-170000" -Line @("the last part")

            $Result = Move-SessionLogFileToPart -Directory $Script:Folder

            (Split-Path $Result -Leaf) | Should -BeExactly "OmadaSqlTroubleshooter_20260913-170000_003.log"
        }
    }

    Context "The active file is genuinely held open" {

        It "leaves it exactly where it is, because the OS refuses the rename while the handle is open" {
            $Live = Open-SessionLogFileWriter -Path $Script:ActivePath -SessionKey "20260913-170000" -StartTime ([datetime]::new(2026, 9, 13, 17, 0, 0)) -ProcessId 4242
            $Script:Writers.Add($Live.Writer)
            $Live.Writer.WriteLine("still being written")

            $Result = Move-SessionLogFileToPart -Directory $Script:Folder

            $Result | Should -BeNullOrEmpty
            Test-Path -LiteralPath $Script:ActivePath | Should -BeTrue
            $Live.Writer.WriteLine("and carries on afterwards")
        }
    }
}
