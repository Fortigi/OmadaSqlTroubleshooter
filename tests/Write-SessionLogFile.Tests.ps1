#Requires -Version 7.0
# Tests for the session log file writer of issue #121.
#
# Real files in a real temporary folder, no mocked file system: "the file survives a crash" is a
# statement about bytes on disk, and a mock cannot make it true or false.
#
# The four claims worth reading first:
#
#   * a line written before the file has been opened is not lost - start-up is exactly where a
#     session dies, so the lines from before the configuration was read have to reach the file too;
#   * the file has its OWN level, which may be more verbose than the log window's;
#   * every line is on disk before the call returns, readable by another handle, with nothing
#     stopped or disposed - that is the whole crash-survival requirement;
#   * a session that reaches the size ceiling rolls into a new part instead of stopping, because
#     the end of a session is the part a crash report needs.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Test-LogLevelThreshold.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SessionLogFileName.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-SessionLogFile.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    function New-SessionLogFolder {
        $Folder = Join-Path ([System.IO.Path]::GetTempPath()) -ChildPath ("OmadaSqlLogWrite_{0}" -f ([guid]::NewGuid().ToString("N")))
        New-Item -Path $Folder -ItemType Directory -Force | Out-Null
        return $Folder
    }

    # Opens the file for this test's state without going through Start-SessionLogFile, which reads
    # the configuration. The writer is the subject here; start-up is Start-SessionLogFile.Tests.ps1.
    function Open-TestSessionLogFile {
        param(
            [string]$Folder,
            [string]$LogLevel = "DEBUG",
            [int]$MaxSizeMegabytes = 20
        )

        # Continues the state already in play, exactly as Start-SessionLogFile does, so the lines
        # held before the file opened are still there to be flushed.
        $State = $Script:SessionLogFile
        if ($null -eq $State) {
            $State = New-SessionLogFileState -LogLevel $LogLevel
        }

        $State.LogLevel = $LogLevel
        $State.Directory = $Folder
        $State.MaxBytes = [long]$MaxSizeMegabytes * 1MB
        $State.Path = Join-Path $Folder -ChildPath (Get-SessionLogFileName -StartTime $State.StartTime -ProcessId $State.ProcessId -Part $State.Part)
        $State.Writer = Open-SessionLogFileWriter -Path $State.Path
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
        try {
            $Reader = [System.IO.StreamReader]::new($Stream)
            try {
                return $Reader.ReadToEnd()
            }
            finally {
                $Reader.Dispose()
            }
        }
        finally {
            $Stream.Dispose()
        }
    }
}

Describe "Write-SessionLogFile" {

    BeforeEach {
        $Script:Folder = New-SessionLogFolder
        $Script:SessionLogFile = $null
    }

    AfterEach {
        Stop-SessionLogFile
        Remove-Item -Path $Script:Folder -Recurse -Force -ErrorAction SilentlyContinue
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
            # The level the file ends up running at is only known once the configuration has been
            # read, which is after these lines were held.
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
            # The window is at WARNING - the shipped default - and the file is at VERBOSE, so the
            # session that turns out to be interesting has detail the window never showed.
            $Script:RunTimeConfig = [PSCustomObject]@{ Logging = [PSCustomObject]@{ LogLevelSetting = "WARNING" } }
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder -LogLevel "VERBOSE"

            Write-SessionLogFile -Line "a verbose line the window never showed" -LogType "VERBOSE"

            Read-SessionLogFileWhileOpen -Path $Script:SessionLogFile.Path | Should -Match "a verbose line the window never showed"
        }
    }

    Context "Flushed as it goes" {

        It "has the line on disk before the call returns, with nothing closed or disposed" {
            # This is the crash-survival requirement stated as an assertion: no Stop, no Dispose, no
            # end of session - just the bytes, readable by another handle.
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder

            Write-SessionLogFile -Line "the last thing before the crash" -LogType "ERROR"

            Read-SessionLogFileWhileOpen -Path $Script:SessionLogFile.Path | Should -Match "the last thing before the crash"
        }

        It "keeps every line written so far, in order" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder

            foreach ($Index in 1..20) {
                Write-SessionLogFile -Line ("line {0}" -f $Index) -LogType "INFO"
            }

            $Line = (Read-SessionLogFileWhileOpen -Path $Script:SessionLogFile.Path) -split "`r?`n" | Where-Object { $_ }
            ($Line | Measure-Object).Count | Should -Be 20
            $Line[0] | Should -BeExactly "line 1"
            $Line[19] | Should -BeExactly "line 20"
        }
    }

    Context "The size ceiling" {

        It "rolls into a new part instead of stopping, so the end of the session survives" {
            # 1 MB ceiling, then write past it. A ceiling that simply stopped writing would throw
            # away precisely the part a crash report is about.
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder -MaxSizeMegabytes 1
            $FirstPath = $Script:SessionLogFile.Path
            $Padding = "x" * 1024

            foreach ($Index in 1..1100) {
                Write-SessionLogFile -Line $Padding -LogType "INFO"
            }
            Write-SessionLogFile -Line "after the ceiling" -LogType "INFO"

            $Script:SessionLogFile.Part | Should -BeGreaterThan 1
            $Script:SessionLogFile.Path | Should -Not -BeExactly $FirstPath
            Read-SessionLogFileWhileOpen -Path $Script:SessionLogFile.Path | Should -Match "after the ceiling"
        }

        It "keeps each part under the ceiling" {
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder -MaxSizeMegabytes 1
            $Padding = "x" * 1024

            foreach ($Index in 1..1100) {
                Write-SessionLogFile -Line $Padding -LogType "INFO"
            }

            foreach ($File in (Get-ChildItem -Path $Script:Folder -File)) {
                # One line of slack: the ceiling is checked after the line that crossed it.
                $File.Length | Should -BeLessOrEqual (1MB + 2048)
            }
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
            # TextWriter::Synchronized makes WriteLine atomic and nothing else. BytesWritten, Part,
            # Path and the Writer reference itself are all read-modify-written around it, and the
            # rollover disposes and replaces the writer - so two threads rolling at once could lose
            # lines or abandon the file outright.
            $Script:SessionLogFile = New-SessionLogFileState -LogLevel "DEBUG"

            $Script:SessionLogFile.SyncRoot | Should -Not -BeNullOrEmpty
        }

        It "waits for that lock rather than writing through it" {
            # A real wait, not a claim about the source: another thread holds the lock for 400ms and
            # the write must not return before it is released.
            $Script:SessionLogFile = Open-TestSessionLogFile -Folder $Script:Folder
            # A runspace, not a bare [System.Threading.Thread]: a PowerShell script block has no
            # runspace on a raw .NET thread and the process dies trying. The SyncRoot instance is
            # passed by reference, so both sides lock the same object.
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
                # Let the holder actually take the lock before the timed write starts.
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
