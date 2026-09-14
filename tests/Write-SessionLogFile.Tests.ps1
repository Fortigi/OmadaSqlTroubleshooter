#Requires -Version 7.0
# Tests for the session log file writer of issue #121.
#
# Real files in a real temporary folder, no mocked file system: "the file survives a crash" and
# "nothing is lost across a split" are statements about bytes on disk, and a mock cannot make them
# true or false.
#
# The claims worth reading first:
#
#   * a line written before the file has been opened is not lost;
#   * the file has its OWN level, which may be more verbose than the log window's;
#   * every line is on disk before the call returns, readable by another handle;
#   * past the size limit the file is split into a numbered part and writing continues in a fresh
#     OmadaSqlTroubleshooter.log, with the lines on either side of the boundary contiguous.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Test-LogLevelThreshold.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SessionLogFileName.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-SessionLogFile.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    # Opens the file for this test's state without going through Start-SessionLogFile, which reads
    # the configuration. -Numbered opens it the way a second instance does.
    function Open-TestSessionLogFile {
        param(
            [string]$Folder,
            [string]$LogLevel = "DEBUG",
            [long]$MaxBytes = 5MB,
            [switch]$Numbered
        )

        $State = $Script:SessionLogFile
        if ($null -eq $State) {
            $State = New-SessionLogFileState -LogLevel $LogLevel
        }

        $State.LogLevel = $LogLevel
        $State.Directory = $Folder
        $State.MaxBytes = $MaxBytes
        $State.SessionKey = New-SessionLogFileSessionKey -StartTime $State.StartTime
        $State.Part = 1
        $State.UsesActiveName = -not $Numbered
        if ($Numbered) {
            $State.Path = Join-Path $Folder -ChildPath (Get-SessionLogFileName -SessionKey $State.SessionKey -Part 1)
        }
        else {
            $State.Path = Join-Path $Folder -ChildPath (Get-SessionLogFileName)
        }

        $Opened = Open-SessionLogFileWriter -Path $State.Path -SessionKey $State.SessionKey -StartTime $State.StartTime -ProcessId $State.ProcessId
        $State.Writer = $Opened.Writer
        $State.BytesWritten = $Opened.BytesWritten
        $Script:SessionLogFile = $State

        $Pending = $State.Pending
        $State.Pending = $null
        foreach ($Entry in $Pending) {
            Write-SessionLogFile -Line $Entry.Line -LogType $Entry.LogType
        }

        return $State
    }

    # Reads the file while the application still holds it open, which is what a support engineer
    # does mid-session and what a crash leaves behind.
    function Read-SessionLogFileWhileOpen {
        param([string]$Path)

        $Stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        $Reader = $null
        try {
            $Reader = [System.IO.StreamReader]::new($Stream)
            return $Reader.ReadToEnd()
        }
        finally {
            if ($null -ne $Reader) {
                $Reader.Dispose()
            }

            $Stream.Dispose()
        }
    }

    # The log lines of one part, without its header.
    function Get-SessionLogFileBody {
        param([string]$Path)

        return @((Read-SessionLogFileWhileOpen -Path $Path) -split "`r?`n" | Where-Object { $_ -ne "" } | Select-Object -Skip 1)
    }

    # Every part of the folder in order - numbered parts by name, then the active file - as one body.
    function Get-WholeSessionBody {
        param([string]$Folder)

        $PartName = [System.Collections.Generic.List[string]]::new([string[]]@(Get-ChildItem -LiteralPath $Folder -Filter "OmadaSqlTroubleshooter_*.log" -File | ForEach-Object { $_.Name }))
        $PartName.Sort([System.StringComparer]::Ordinal)

        $Body = [System.Collections.Generic.List[string]]::new()
        foreach ($Name in $PartName) {
            $Body.AddRange([string[]]@(Get-SessionLogFileBody -Path (Join-Path $Folder -ChildPath $Name)))
        }

        $ActivePath = Join-Path $Folder -ChildPath "OmadaSqlTroubleshooter.log"
        if (Test-Path -LiteralPath $ActivePath) {
            $Body.AddRange([string[]]@(Get-SessionLogFileBody -Path $ActivePath))
        }

        return , $Body.ToArray()
    }
}

Describe "Write-SessionLogFile" {

    BeforeEach {
        $Script:Folder = Join-Path ([System.IO.Path]::GetTempPath()) -ChildPath ("OmadaSqlLogWrite_{0}" -f ([guid]::NewGuid().ToString("N")))
        [System.IO.Directory]::CreateDirectory($Script:Folder) | Out-Null
        $Script:SessionLogFile = $null
    }

    AfterEach {
        Stop-SessionLogFile
        Remove-Item -LiteralPath $Script:Folder -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Before the file has been opened" {

        It "holds the line rather than losing it" {
            $Script:SessionLogFile = New-SessionLogFileState -LogLevel "DEBUG"

            Write-SessionLogFile -Line "a line from start-up" -LogType "DEBUG"

            $Script:SessionLogFile.Pending.Count | Should -Be 1
        }

        It "writes the held lines to the file once it is opened" {
            $Script:SessionLogFile = New-SessionLogFileState -LogLevel "DEBUG"
            Write-SessionLogFile -Line "a line from start-up" -LogType "DEBUG"

            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder

            Read-SessionLogFileWhileOpen -Path $Script:SessionLogFile.Path | Should -Match "a line from start-up"
        }

        It "stops holding lines once the buffer is full, so a file that never opens cannot grow without bound" {
            $Script:SessionLogFile = New-SessionLogFileState -LogLevel "DEBUG"
            $Limit = $Script:SessionLogFile.PendingLimit

            foreach ($Index in 1..($Limit + 50)) {
                Write-SessionLogFile -Line ("line {0}" -f $Index) -LogType "DEBUG"
            }

            $Script:SessionLogFile.Pending.Count | Should -Be $Limit
        }

        It "applies the resolved level to the held lines, not the provisional one" {
            $Script:SessionLogFile = New-SessionLogFileState -LogLevel "DEBUG"
            Write-SessionLogFile -Line "a held debug line" -LogType "DEBUG"
            Write-SessionLogFile -Line "a held error line" -LogType "ERROR"

            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder -LogLevel "ERROR"

            $Content = Read-SessionLogFileWhileOpen -Path $Script:SessionLogFile.Path
            $Content | Should -Match "a held error line"
            $Content | Should -Not -Match "a held debug line"
        }
    }

    Context "The file's own level" {

        It "writes a line at or above the file's level" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder -LogLevel "DEBUG"

            Write-SessionLogFile -Line "a debug line" -LogType "DEBUG"

            Read-SessionLogFileWhileOpen -Path $Script:SessionLogFile.Path | Should -Match "a debug line"
        }

        It "skips a line below the file's level" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder -LogLevel "WARNING"

            Write-SessionLogFile -Line "a debug line" -LogType "DEBUG"

            Read-SessionLogFileWhileOpen -Path $Script:SessionLogFile.Path | Should -Not -Match "a debug line"
        }

        It "is independent of the log window's level, which is the point of the setting" {
            $Script:RunTimeConfig = [PSCustomObject]@{ Logging = [PSCustomObject]@{ LogLevelSetting = "WARNING" } }
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder -LogLevel "VERBOSE"

            Write-SessionLogFile -Line "a verbose line the window never showed" -LogType "VERBOSE"

            Read-SessionLogFileWhileOpen -Path $Script:SessionLogFile.Path | Should -Match "a verbose line the window never showed"
        }
    }

    Context "Flushed as it goes" {

        It "has the line on disk before the call returns, with nothing closed or disposed" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder

            Write-SessionLogFile -Line "the last thing before the crash" -LogType "ERROR"

            Read-SessionLogFileWhileOpen -Path $Script:SessionLogFile.Path | Should -Match "the last thing before the crash"
        }

        It "starts with the session header, then every line written so far, in order" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder

            foreach ($Index in 1..20) {
                Write-SessionLogFile -Line ("line {0}" -f $Index) -LogType "INFO"
            }

            (Read-SessionLogFileHeader -Path $Script:SessionLogFile.Path).SessionKey | Should -BeExactly $Script:SessionLogFile.SessionKey
            $Body = Get-SessionLogFileBody -Path $Script:SessionLogFile.Path
            $Body.Count | Should -Be 20
            $Body[0] | Should -BeExactly "line 1"
            $Body[19] | Should -BeExactly "line 20"
        }
    }

    Context "Splitting at the size limit" {

        It "renames the full part to _<session>_001 and carries on in a fresh OmadaSqlTroubleshooter.log" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder -MaxBytes 4096
            $Padding = "x" * 100

            foreach ($Index in 1..60) {
                Write-SessionLogFile -Line $Padding -LogType "INFO"
            }

            $FirstPart = Join-Path $Script:Folder -ChildPath (Get-SessionLogFileName -SessionKey $Script:SessionLogFile.SessionKey -Part 1)
            Test-Path -LiteralPath $FirstPart | Should -BeTrue
            $Script:SessionLogFile.Path | Should -BeExactly (Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter.log")
            Test-Path -LiteralPath $Script:SessionLogFile.Path | Should -BeTrue
            $Script:SessionLogFile.Part | Should -Be 2
        }

        It "keeps the lines on either side of every split contiguous: nothing lost, nothing written twice" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder -MaxBytes 2048

            foreach ($Index in 1..1000) {
                Write-SessionLogFile -Line ("line {0:0000}" -f $Index) -LogType "INFO"
            }

            @(Get-ChildItem -LiteralPath $Script:Folder -Filter "OmadaSqlTroubleshooter_*.log" -File).Count | Should -BeGreaterThan 2
            $Expected = 1..1000 | ForEach-Object { "line {0:0000}" -f $_ }
            ((Get-WholeSessionBody -Folder $Script:Folder) -join "`n") | Should -BeExactly ($Expected -join "`n")
        }

        It "starts every part with the session's header" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder -MaxBytes 2048

            foreach ($Index in 1..500) {
                Write-SessionLogFile -Line ("line {0:0000}" -f $Index) -LogType "INFO"
            }

            foreach ($File in (Get-ChildItem -LiteralPath $Script:Folder -File)) {
                (Read-SessionLogFileHeader -Path $File.FullName).SessionKey | Should -BeExactly $Script:SessionLogFile.SessionKey
            }
        }

        It "counts exactly the bytes that reach the file, header and line endings included" {
            # The split decision is taken on this count, never on the file's measured length, so a
            # count that drifts from the file splits at the wrong size.
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder

            Write-SessionLogFile -Line "plain ascii" -LogType "INFO"
            Write-SessionLogFile -Line "accented: caf$([char]0x00E9) na$([char]0x00EF)ve" -LogType "INFO"
            Write-SessionLogFile -Line "" -LogType "INFO"

            $Script:SessionLogFile.BytesWritten | Should -Be ([System.IO.FileInfo]::new($Script:SessionLogFile.Path).Length)
        }

        It "keeps each finished part within one line of the limit" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder -MaxBytes 2048

            foreach ($Index in 1..500) {
                Write-SessionLogFile -Line ("line {0:0000}" -f $Index) -LogType "INFO"
            }

            foreach ($File in (Get-ChildItem -LiteralPath $Script:Folder -Filter "OmadaSqlTroubleshooter_*.log" -File)) {
                $File.Length | Should -BeLessOrEqual (2048 + 64)
            }
        }

        It "numbers a second instance's parts from 001 and continues at 002" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder -MaxBytes 1024 -Numbered
            $SessionKey = $Script:SessionLogFile.SessionKey

            foreach ($Index in 1..120) {
                Write-SessionLogFile -Line ("line {0:0000}" -f $Index) -LogType "INFO"
            }

            Test-Path -LiteralPath (Join-Path $Script:Folder -ChildPath (Get-SessionLogFileName -SessionKey $SessionKey -Part 1)) | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $Script:Folder -ChildPath (Get-SessionLogFileName -SessionKey $SessionKey -Part 2)) | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter.log") | Should -BeFalse
            $Expected = 1..120 | ForEach-Object { "line {0:0000}" -f $_ }
            ((Get-WholeSessionBody -Folder $Script:Folder) -join "`n") | Should -BeExactly ($Expected -join "`n")
        }

        It "keeps writing the same file, losing nothing, when something holds it and the rename is refused" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder -MaxBytes 1024
            # A reader that does not share Delete - the way many editors open a file.
            $Holder = [System.IO.FileStream]::new($Script:SessionLogFile.Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                foreach ($Index in 1..200) {
                    Write-SessionLogFile -Line ("line {0:0000}" -f $Index) -LogType "INFO"
                }
            }
            finally {
                $Holder.Dispose()
            }

            $Script:SessionLogFile.Failed | Should -BeFalse
            @(Get-ChildItem -LiteralPath $Script:Folder -Filter "OmadaSqlTroubleshooter_*.log" -File).Count | Should -Be 0
            $Expected = 1..200 | ForEach-Object { "line {0:0000}" -f $_ }
            ((Get-WholeSessionBody -Folder $Script:Folder) -join "`n") | Should -BeExactly ($Expected -join "`n")
        }

        It "recreates the active file with its header when it vanished before the split could rename it" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder -MaxBytes 1024
            $ActivePath = $Script:SessionLogFile.Path
            # Nothing holds the active file between the split closing it and renaming it. Reproduce
            # that instant: close it, delete it, and let the session write through a stand-in writer
            # until the next split finds the file gone.
            $Script:SessionLogFile.Writer.Dispose()
            Remove-Item -LiteralPath $ActivePath -Force
            $StandIn = Open-SessionLogFileWriter -Path (Join-Path $Script:Folder -ChildPath "stand-in.txt") -SessionKey $Script:SessionLogFile.SessionKey -StartTime $Script:SessionLogFile.StartTime -ProcessId $Script:SessionLogFile.ProcessId
            $Script:SessionLogFile.Writer = $StandIn.Writer
            $Script:SessionLogFile.BytesWritten = [long]0

            # About 11 bytes a line against a 1024-byte limit: one split, after roughly 93 lines, and
            # not a second one before the assertions.
            foreach ($Index in 1..120) {
                Write-SessionLogFile -Line ("line {0:0000}" -f $Index) -LogType "INFO"
            }

            $Script:SessionLogFile.Failed | Should -BeFalse
            (Read-SessionLogFileHeader -Path $ActivePath).SessionKey | Should -BeExactly $Script:SessionLogFile.SessionKey
        }

        It "never creates a file when asked to reopen one that does not exist" {
            $MissingPath = Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter.log"

            { Open-SessionLogFileWriter -Path $MissingPath -Append } | Should -Throw
            Test-Path -LiteralPath $MissingPath | Should -BeFalse
        }

        It "stops splitting at part 999 but never stops writing" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder -MaxBytes 1024 -Numbered
            $Script:SessionLogFile.Part = 999

            foreach ($Index in 1..100) {
                Write-SessionLogFile -Line ("line {0:0000}" -f $Index) -LogType "INFO"
            }

            @(Get-ChildItem -LiteralPath $Script:Folder -File).Count | Should -Be 1
            (Get-SessionLogFileBody -Path $Script:SessionLogFile.Path).Count | Should -Be 100
        }
    }

    Context "It must never take the application down with it" {

        It "does nothing, and throws nothing, when no session log file is in play" {
            $Script:SessionLogFile = $null

            { Write-SessionLogFile -Line "nowhere to go" -LogType "ERROR" } | Should -Not -Throw
        }

        It "gives up quietly, and stays given up, when the writer fails" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder
            $Script:SessionLogFile.Writer.Dispose()

            { Write-SessionLogFile -Line "into a closed writer" -LogType "ERROR" } | Should -Not -Throw
            $Script:SessionLogFile.Failed | Should -BeTrue

            { Write-SessionLogFile -Line "and again" -LogType "ERROR" } | Should -Not -Throw
        }
    }

    Context "Stopping" {

        It "closes the file and ignores anything written afterwards" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder
            $Path = $Script:SessionLogFile.Path
            Write-SessionLogFile -Line "before the close" -LogType "INFO"

            Stop-SessionLogFile
            Write-SessionLogFile -Line "after the close" -LogType "INFO"

            $Content = Get-Content -LiteralPath $Path -Raw
            $Content | Should -Match "before the close"
            $Content | Should -Not -Match "after the close"
        }

        It "can be called twice" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder

            Stop-SessionLogFile
            { Stop-SessionLogFile } | Should -Not -Throw
        }

        It "can be called when there is no session log file at all" {
            $Script:SessionLogFile = $null

            { Stop-SessionLogFile } | Should -Not -Throw
        }
    }

    Context "Concurrency" {

        It "carries a lock object for the state the synchronized writer does not cover" {
            $Script:SessionLogFile = New-SessionLogFileState -LogLevel "DEBUG"

            $Script:SessionLogFile.SyncRoot | Should -Not -BeNullOrEmpty
        }

        It "waits for that lock rather than writing through it" {
            # A real wait, not a claim about the source: another thread holds the lock for 400ms and
            # the write must not return before it is released.
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder
            # A runspace, not a bare [System.Threading.Thread]: a PowerShell script block has no
            # runspace on a raw .NET thread and the process dies trying.
            $Holder = [powershell]::Create()
            $Holder.AddScript({
                    param($SyncRoot)
                    [System.Threading.Monitor]::Enter($SyncRoot)
                    try {
                        Start-Sleep -Milliseconds 400
                    }
                    finally {
                        [System.Threading.Monitor]::Exit($SyncRoot)
                    }
                }).AddArgument($Script:SessionLogFile.SyncRoot) | Out-Null

            try {
                $Handle = $Holder.BeginInvoke()
                Start-Sleep -Milliseconds 150
                $Elapsed = Measure-Command { Write-SessionLogFile -Line "behind the lock" -LogType "INFO" }
                $Holder.EndInvoke($Handle)
            }
            finally {
                $Holder.Dispose()
            }

            $Elapsed.TotalMilliseconds | Should -BeGreaterThan 200
            Read-SessionLogFileWhileOpen -Path $Script:SessionLogFile.Path | Should -Match "behind the lock"
        }

        It "releases the lock when the write fails, so one failure does not deadlock the application" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder
            $Script:SessionLogFile.Writer.Dispose()

            Write-SessionLogFile -Line "into a closed writer" -LogType "INFO"

            $Taken = [System.Threading.Monitor]::TryEnter($Script:SessionLogFile.SyncRoot, 1000)
            if ($Taken) {
                [System.Threading.Monitor]::Exit($Script:SessionLogFile.SyncRoot)
            }

            $Taken | Should -BeTrue
        }
    }

    Context "Required parameters" {

        It "declares <Parameter> mandatory" -ForEach @(
            @{ Parameter = "Line" }
            @{ Parameter = "LogType" }
        ) {
            (Get-Command Write-SessionLogFile).Parameters[$Parameter].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }
    }
}
