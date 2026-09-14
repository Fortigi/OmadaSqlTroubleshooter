#Requires -Version 7.0
# Tests for opening a session's log file: rotation of the previous session's file, and the second
# instance (issue #121, as the maintainer revised it).
#
# Real files and real handles. "A live file is never renamed" is a statement about what the operating
# system allows while another handle is open, and only a second real handle can make it true or false.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Get-SessionLogFileName.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-SessionLogFile.ps1")
    . (Join-Path $PrivatePath -ChildPath "Open-SessionLogFile.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    # A file some earlier session wrote and closed: header, then lines.
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

    function Read-FileWhileOpen {
        param([string]$Path)

        $Stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        try {
            $Reader = [System.IO.StreamReader]::new($Stream)
            return $Reader.ReadToEnd()
        }
        finally {
            $Stream.Dispose()
        }
    }

    function Invoke-OpenSessionLogFile {
        $Result = Open-SessionLogFile -Directory $Script:Folder -StartTime $Script:StartTime -ProcessId 5151
        $Script:Writers.Add($Result.Writer)
        return $Result
    }
}

Describe "Open-SessionLogFile" {

    BeforeEach {
        $Script:Folder = Join-Path ([System.IO.Path]::GetTempPath()) -ChildPath ("OmadaSqlLogOpen_{0}" -f ([guid]::NewGuid().ToString("N")))
        [System.IO.Directory]::CreateDirectory($Script:Folder) | Out-Null
        $Script:ActivePath = Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter.log"
        $Script:StartTime = [datetime]::new(2026, 9, 14, 8, 5, 3)
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

    Context "An empty folder" {

        It "writes OmadaSqlTroubleshooter.log as part 1 of a new session" {
            $Result = Invoke-OpenSessionLogFile

            $Result.Path | Should -BeExactly $Script:ActivePath
            $Result.UsesActiveName | Should -BeTrue
            $Result.SessionKey | Should -BeExactly "20260914-080503"
            $Result.Part | Should -Be 1
            $Result.RotatedPath | Should -BeNullOrEmpty
        }

        It "records the session in the file's first line" {
            Invoke-OpenSessionLogFile | Out-Null

            (Read-SessionLogFileHeader -Path $Script:ActivePath).SessionKey | Should -BeExactly "20260914-080503"
        }
    }

    Context "Two sessions in the same second" {

        It "never takes the key of a session already in the folder" {
            New-ClosedSessionLogFile -Path (Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter_20260914-080503_001.log") -SessionKey "20260914-080503"

            (Invoke-OpenSessionLogFile).SessionKey | Should -BeExactly "20260914-080503b"
        }
    }

    Context "Rotating the previous session's file" {

        It "renames it to part 001 of its own session and opens a fresh file" {
            New-ClosedSessionLogFile -Path $Script:ActivePath -SessionKey "20260913-170000" -Line @("from the previous session")
            $Expected = Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter_20260913-170000_001.log"

            $Result = Invoke-OpenSessionLogFile

            $Result.RotatedPath | Should -BeExactly $Expected
            Read-FileWhileOpen -Path $Expected | Should -Match "from the previous session"
            $Result.Path | Should -BeExactly $Script:ActivePath
            (Read-SessionLogFileHeader -Path $Script:ActivePath).SessionKey | Should -BeExactly "20260914-080503"
            Read-FileWhileOpen -Path $Script:ActivePath | Should -Not -Match "from the previous session"
        }

        It "continues the part numbers of a session that had already split" {
            New-ClosedSessionLogFile -Path (Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter_20260913-170000_001.log") -SessionKey "20260913-170000"
            New-ClosedSessionLogFile -Path (Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter_20260913-170000_002.log") -SessionKey "20260913-170000"
            New-ClosedSessionLogFile -Path $Script:ActivePath -SessionKey "20260913-170000" -Line @("the last part")

            $Result = Invoke-OpenSessionLogFile

            (Split-Path $Result.RotatedPath -Leaf) | Should -BeExactly "OmadaSqlTroubleshooter_20260913-170000_003.log"
        }

        It "takes the session from the header, not from the file system's dates" {
            # NTFS tunneling can give a file created under a just-renamed name the old file's
            # CreationTime, which is exactly what rotation does - so no file system date is trusted.
            New-ClosedSessionLogFile -Path $Script:ActivePath -SessionKey "20260913-170000"
            [System.IO.File]::SetCreationTime($Script:ActivePath, [datetime]::new(2020, 1, 1))
            [System.IO.File]::SetLastWriteTime($Script:ActivePath, [datetime]::new(2020, 1, 1))

            $Result = Invoke-OpenSessionLogFile

            (Split-Path $Result.RotatedPath -Leaf) | Should -BeExactly "OmadaSqlTroubleshooter_20260913-170000_001.log"
        }

        It "falls back to the last write time for a file with no readable header" {
            [System.IO.File]::WriteAllText($Script:ActivePath, "no header here`r`n")
            [System.IO.File]::SetLastWriteTime($Script:ActivePath, [datetime]::new(2026, 9, 10, 11, 12, 13))

            $Result = Invoke-OpenSessionLogFile

            (Split-Path $Result.RotatedPath -Leaf) | Should -BeExactly "OmadaSqlTroubleshooter_20260910-111213_001.log"
            Read-FileWhileOpen -Path $Result.RotatedPath | Should -Match "no header here"
        }

        It "gives a header-less file a key of its own when that second belongs to another session" {
            $Existing = Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter_20260910-111213_001.log"
            New-ClosedSessionLogFile -Path $Existing -SessionKey "20260910-111213" -Line @("another session")
            $ExistingContent = Read-FileWhileOpen -Path $Existing
            [System.IO.File]::WriteAllText($Script:ActivePath, "no header here`r`n")
            [System.IO.File]::SetLastWriteTime($Script:ActivePath, [datetime]::new(2026, 9, 10, 11, 12, 13))

            $Result = Invoke-OpenSessionLogFile

            (Split-Path $Result.RotatedPath -Leaf) | Should -BeExactly "OmadaSqlTroubleshooter_20260910-111213b_001.log"
            Read-FileWhileOpen -Path $Existing | Should -BeExactly $ExistingContent
        }
    }

    Context "A live file is never renamed" {

        It "leaves another instance's open OmadaSqlTroubleshooter.log exactly where it is" {
            $Live = Open-SessionLogFileWriter -Path $Script:ActivePath -SessionKey "20260914-070000" -StartTime ([datetime]::new(2026, 9, 14, 7, 0, 0)) -ProcessId 4242
            $Script:Writers.Add($Live.Writer)
            $Live.Writer.WriteLine("the other instance is still writing")

            $Result = Invoke-OpenSessionLogFile
            $Live.Writer.WriteLine("and carries on afterwards")

            $Result.RotatedPath | Should -BeNullOrEmpty
            $Result.UsesActiveName | Should -BeFalse
            $Result.Part | Should -Be 1
            (Split-Path $Result.Path -Leaf) | Should -BeExactly "OmadaSqlTroubleshooter_20260914-080503_001.log"
            (Read-SessionLogFileHeader -Path $Script:ActivePath).SessionKey | Should -BeExactly "20260914-070000"
            $LiveContent = Read-FileWhileOpen -Path $Script:ActivePath
            $LiveContent | Should -Match "the other instance is still writing"
            $LiveContent | Should -Match "and carries on afterwards"
        }

        It "gives the second instance a different key from the running session, even in the same second" {
            $Live = Open-SessionLogFileWriter -Path $Script:ActivePath -SessionKey "20260914-080503" -StartTime $Script:StartTime -ProcessId 4242
            $Script:Writers.Add($Live.Writer)

            $Result = Invoke-OpenSessionLogFile

            $Result.SessionKey | Should -BeExactly "20260914-080503b"
            (Split-Path $Result.Path -Leaf) | Should -BeExactly "OmadaSqlTroubleshooter_20260914-080503b_001.log"
        }

        It "is refused by the operating system itself while the writer's handle is open" {
            # The guarantee does not rest on this module's own checks: the writer does not share
            # Delete, so any rename - by this code, another instance or a user - is refused.
            $Live = Open-SessionLogFileWriter -Path $Script:ActivePath -SessionKey "20260914-070000" -StartTime ([datetime]::new(2026, 9, 14, 7, 0, 0)) -ProcessId 4242
            $Script:Writers.Add($Live.Writer)

            { [System.IO.File]::Move($Script:ActivePath, (Join-Path $Script:Folder -ChildPath "moved.log")) } | Should -Throw
            Test-Path -LiteralPath $Script:ActivePath | Should -BeTrue
        }

        It "still lets somebody tail the file while it is being written" {
            $Live = Open-SessionLogFileWriter -Path $Script:ActivePath -SessionKey "20260914-070000" -StartTime ([datetime]::new(2026, 9, 14, 7, 0, 0)) -ProcessId 4242
            $Script:Writers.Add($Live.Writer)
            $Tail = [System.IO.FileStream]::new($Script:ActivePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $Live.Writer.WriteLine("written while tailed")
                $TailReader = [System.IO.StreamReader]::new($Tail)
                $TailReader.ReadToEnd() | Should -Match "written while tailed"
            }
            finally {
                $Tail.Dispose()
            }
        }
    }

    Context "Required parameters" {

        It "declares <Parameter> mandatory" -ForEach @(
            @{ Parameter = "Directory" }
            @{ Parameter = "StartTime" }
            @{ Parameter = "ProcessId" }
        ) {
            (Get-Command Open-SessionLogFile).Parameters[$Parameter].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }
    }
}
