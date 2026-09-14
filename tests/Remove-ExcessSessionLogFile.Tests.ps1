#Requires -Version 7.0
# Tests for start-up pruning of session log files (issue #121, as the maintainer revised it):
# retention by session count only, whole sessions at a time, oldest start time first.
#
# Real folders with real files. The assertions that matter most are the ones about what must survive:
# files the application did not write, the current session, and a session still being written.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Get-SessionLogFileName.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-SessionLogFile.ps1")
    . (Join-Path $PrivatePath -ChildPath "Remove-ExcessSessionLogFile.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    function New-TestSessionLogFile {
        param(
            [string]$Folder,
            [string]$SessionKey,
            [int]$PartCount = 1,
            [switch]$WithActiveFile
        )

        $StartTime = [datetime]::ParseExact($SessionKey.Substring(0, 15), "yyyyMMdd-HHmmss", [System.Globalization.CultureInfo]::InvariantCulture)
        $Path = [System.Collections.Generic.List[string]]::new()
        foreach ($Part in 1..$PartCount) {
            $Path.Add((Join-Path $Folder -ChildPath (Get-SessionLogFileName -SessionKey $SessionKey -Part $Part)))
        }

        if ($WithActiveFile) {
            $Path.Add((Join-Path $Folder -ChildPath (Get-SessionLogFileName)))
        }

        foreach ($FilePath in $Path) {
            $Opened = Open-SessionLogFileWriter -Path $FilePath -SessionKey $SessionKey -StartTime $StartTime -ProcessId 4242
            $Opened.Writer.WriteLine("a line")
            $Opened.Writer.Dispose()
        }

        return , $Path.ToArray()
    }

    function Get-SessionKeyInFolder {
        param([string]$Folder)

        return @(Get-SessionLogFileInventory -Directory $Folder | Where-Object { -not $_.IsActive } | ForEach-Object { $_.SessionKey } | Sort-Object -Unique)
    }
}

Describe "Remove-ExcessSessionLogFile" {

    BeforeEach {
        $Script:Folder = Join-Path ([System.IO.Path]::GetTempPath()) -ChildPath ("OmadaSqlLogPrune_{0}" -f ([guid]::NewGuid().ToString("N")))
        [System.IO.Directory]::CreateDirectory($Script:Folder) | Out-Null
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

    Context "Retention by session count" {

        It "keeps every part of the newest sessions and deletes older sessions whole" {
            $Oldest = New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260901-080000" -PartCount 3
            $Second = New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260902-080000" -PartCount 2
            foreach ($Day in 3..11) {
                New-TestSessionLogFile -Folder $Script:Folder -SessionKey ("202609{0:00}-080000" -f $Day) | Out-Null
            }

            $Newest = New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260912-080000" -PartCount 4

            Remove-ExcessSessionLogFile -Directory $Script:Folder -RetentionCount 10 | Out-Null

            foreach ($FilePath in $Oldest + $Second) {
                Test-Path -LiteralPath $FilePath | Should -BeFalse
            }

            foreach ($FilePath in $Newest) {
                Test-Path -LiteralPath $FilePath | Should -BeTrue
            }

            (Get-SessionKeyInFolder -Folder $Script:Folder).Count | Should -Be 10
        }

        It "counts sessions, not files, so one long session does not push out older ones" {
            $Older = New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260901-080000"
            New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260902-080000" -PartCount 30 | Out-Null

            Remove-ExcessSessionLogFile -Directory $Script:Folder -RetentionCount 2 | Out-Null

            Test-Path -LiteralPath $Older[0] | Should -BeTrue
            (Get-ChildItem -LiteralPath $Script:Folder -File | Measure-Object).Count | Should -Be 31
        }

        It "orders by the start time in the name, not by file system dates" {
            $OlderByName = New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260901-080000"
            $NewerByName = New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260902-080000"
            [System.IO.File]::SetLastWriteTime($NewerByName[0], [datetime]::new(2001, 1, 1))
            [System.IO.File]::SetCreationTime($NewerByName[0], [datetime]::new(2001, 1, 1))

            Remove-ExcessSessionLogFile -Directory $Script:Folder -RetentionCount 1 | Out-Null

            Test-Path -LiteralPath $OlderByName[0] | Should -BeFalse
            Test-Path -LiteralPath $NewerByName[0] | Should -BeTrue
        }

        It "orders a same-second session after the plain key" {
            $First = New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260914-080503"
            $Second = New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260914-080503b"

            Remove-ExcessSessionLogFile -Directory $Script:Folder -RetentionCount 1 | Out-Null

            Test-Path -LiteralPath $First[0] | Should -BeFalse
            Test-Path -LiteralPath $Second[0] | Should -BeTrue
        }

        It "counts OmadaSqlTroubleshooter.log as part of the session its header names" {
            $Older = New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260901-080000" -WithActiveFile
            New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260902-080000" | Out-Null

            Remove-ExcessSessionLogFile -Directory $Script:Folder -RetentionCount 1 | Out-Null

            foreach ($FilePath in $Older) {
                Test-Path -LiteralPath $FilePath | Should -BeFalse
            }
        }
    }

    Context "What it must never delete" {

        It "leaves every file that is not one of the application's own names" {
            $Foreign = @(
                "my-own-notes.log"
                "OmadaSqlTroubleshooter_backup.log"
                "OmadaSqlTroubleshooter_20260801-080000_pid4242_001.log"
                "OmadaSqlTroubleshooter_20260801-080000_1000.log"
                "OmadaSqlTroubleshooter.log.bak"
            ) | ForEach-Object {
                $FilePath = Join-Path $Script:Folder -ChildPath $_
                [System.IO.File]::WriteAllText($FilePath, "keep me")
                $FilePath
            }

            foreach ($Day in 1..3) {
                New-TestSessionLogFile -Folder $Script:Folder -SessionKey ("202609{0:00}-080000" -f $Day) | Out-Null
            }

            Remove-ExcessSessionLogFile -Directory $Script:Folder -RetentionCount 1 | Out-Null

            foreach ($FilePath in $Foreign) {
                Test-Path -LiteralPath $FilePath | Should -BeTrue
            }

            (Get-SessionKeyInFolder -Folder $Script:Folder).Count | Should -Be 1
        }

        It "leaves the current session, even when it is the oldest" {
            $Current = New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260901-080000" -PartCount 2
            New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260902-080000" | Out-Null

            Remove-ExcessSessionLogFile -Directory $Script:Folder -RetentionCount 1 -CurrentSessionKey "20260901-080000" | Out-Null

            foreach ($FilePath in $Current) {
                Test-Path -LiteralPath $FilePath | Should -BeTrue
            }
        }

        It "leaves a session another instance is still writing, including its finished parts" {
            $StillRunning = New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260901-080000"
            $LivePart = Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter_20260901-080000_002.log"
            $Live = Open-SessionLogFileWriter -Path $LivePart -SessionKey "20260901-080000" -StartTime ([datetime]::new(2026, 9, 1, 8, 0, 0)) -ProcessId 4242
            $Script:Writers.Add($Live.Writer)
            $Middle = New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260902-080000"
            $Newest = New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260903-080000"

            # Two to keep, three present: the oldest cannot go because it is in use, so the next
            # oldest goes instead. The in-use session still counts toward the two.
            Remove-ExcessSessionLogFile -Directory $Script:Folder -RetentionCount 2 | Out-Null

            Test-Path -LiteralPath $StillRunning[0] | Should -BeTrue
            Test-Path -LiteralPath $LivePart | Should -BeTrue
            Test-Path -LiteralPath $Middle[0] | Should -BeFalse
            Test-Path -LiteralPath $Newest[0] | Should -BeTrue
        }

        It "leaves an OmadaSqlTroubleshooter.log that has no readable header" {
            $Active = Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter.log"
            [System.IO.File]::WriteAllText($Active, "no header")
            New-TestSessionLogFile -Folder $Script:Folder -SessionKey "20260901-080000" | Out-Null

            Remove-ExcessSessionLogFile -Directory $Script:Folder -RetentionCount 1 | Out-Null

            Test-Path -LiteralPath $Active | Should -BeTrue
        }
    }

    Context "A folder it cannot use" {

        It "does not throw when the folder does not exist" {
            { Remove-ExcessSessionLogFile -Directory (Join-Path $Script:Folder -ChildPath "nope") -RetentionCount 10 } | Should -Not -Throw
        }
    }

    Context "Required parameters" {

        It "declares <Parameter> mandatory" -ForEach @(
            @{ Parameter = "Directory" }
            @{ Parameter = "RetentionCount" }
        ) {
            (Get-Command Remove-ExcessSessionLogFile).Parameters[$Parameter].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }
    }
}
