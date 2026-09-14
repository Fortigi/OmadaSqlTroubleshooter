#Requires -Version 7.0
# Tests for the start-up pruning of session log files (issue #121).
#
# "Bounded" is the requirement that keeps an unattended VERBOSE2 session from filling a disk, so
# these tests run against a real folder with real files rather than a mocked file system: the thing
# being asserted IS what happened on disk.
#
# Two of them are the ones that matter. Pruning must never touch a file the application did not
# write - the log folder is a place a user can reasonably drop their own notes - and it must never
# delete the session that is starting right now.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Get-SessionLogFileName.ps1")
    . (Join-Path $PrivatePath -ChildPath "Remove-ExpiredSessionLogFile.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    function New-SessionLogFolder {
        $Folder = Join-Path ([System.IO.Path]::GetTempPath()) -ChildPath ("OmadaSqlLogPrune_{0}" -f ([guid]::NewGuid().ToString("N")))
        New-Item -Path $Folder -ItemType Directory -Force | Out-Null
        return $Folder
    }

    # One session on disk, aged by setting LastWriteTime on every part it has.
    function New-TestSessionLogFile {
        param(
            [string]$Folder,
            [datetime]$StartTime,
            [int]$ProcessId,
            [int]$PartCount = 1,
            [datetime]$LastWriteTime = (Get-Date)
        )

        $Path = @()
        foreach ($Part in 1..$PartCount) {
            $FilePath = Join-Path $Folder -ChildPath (Get-SessionLogFileName -StartTime $StartTime -ProcessId $ProcessId -Part $Part)
            Set-Content -Path $FilePath -Value "line" -Encoding UTF8
            (Get-Item $FilePath).LastWriteTime = $LastWriteTime
            $Path += $FilePath
        }

        # Comma on purpose: a one-part session would otherwise unroll to a bare string, and $Path[0]
        # would be its first character rather than its first file.
        return , $Path
    }
}

Describe "Remove-ExpiredSessionLogFile" {

    BeforeEach {
        $Script:Folder = New-SessionLogFolder
    }

    AfterEach {
        Remove-Item -Path $Script:Folder -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Retention by age" {

        It "deletes a session older than the retention period" {
            $Old = New-TestSessionLogFile -Folder $Script:Folder -StartTime ([datetime]::Now.AddDays(-30)) -ProcessId 101 -LastWriteTime ([datetime]::Now.AddDays(-30))

            Remove-ExpiredSessionLogFile -Directory $Script:Folder -RetentionDays 14 -RetentionCount 100

            Test-Path $Old[0] | Should -BeFalse
        }

        It "keeps a session inside the retention period" {
            $Recent = New-TestSessionLogFile -Folder $Script:Folder -StartTime ([datetime]::Now.AddDays(-2)) -ProcessId 102 -LastWriteTime ([datetime]::Now.AddDays(-2))

            Remove-ExpiredSessionLogFile -Directory $Script:Folder -RetentionDays 14 -RetentionCount 100

            Test-Path $Recent[0] | Should -BeTrue
        }

        It "deletes every part of an expired session, not just the first" {
            $Old = New-TestSessionLogFile -Folder $Script:Folder -StartTime ([datetime]::Now.AddDays(-30)) -ProcessId 103 -PartCount 3 -LastWriteTime ([datetime]::Now.AddDays(-30))

            Remove-ExpiredSessionLogFile -Directory $Script:Folder -RetentionDays 14 -RetentionCount 100

            foreach ($FilePath in $Old) {
                Test-Path $FilePath | Should -BeFalse
            }
        }
    }

    Context "Retention by count" {

        It "keeps only the newest sessions when there are more than the count allows" {
            foreach ($Index in 1..6) {
                New-TestSessionLogFile -Folder $Script:Folder -StartTime ([datetime]::Now.AddHours(-$Index)) -ProcessId (200 + $Index) -LastWriteTime ([datetime]::Now.AddHours(-$Index)) | Out-Null
            }

            Remove-ExpiredSessionLogFile -Directory $Script:Folder -RetentionDays 3650 -RetentionCount 2

            (Get-ChildItem -Path $Script:Folder -File | Measure-Object).Count | Should -Be 2
        }

        It "counts sessions, not files, so one long session does not evict five short ones" {
            # A session that reached the size ceiling has several parts. Counting files would make
            # that single session look like the whole retention budget.
            New-TestSessionLogFile -Folder $Script:Folder -StartTime ([datetime]::Now.AddMinutes(-5)) -ProcessId 301 -PartCount 5 -LastWriteTime ([datetime]::Now.AddMinutes(-5)) | Out-Null
            $Older = New-TestSessionLogFile -Folder $Script:Folder -StartTime ([datetime]::Now.AddHours(-1)) -ProcessId 302 -LastWriteTime ([datetime]::Now.AddHours(-1))

            Remove-ExpiredSessionLogFile -Directory $Script:Folder -RetentionDays 3650 -RetentionCount 2

            Test-Path $Older[0] | Should -BeTrue
            (Get-ChildItem -Path $Script:Folder -File | Measure-Object).Count | Should -Be 6
        }
    }

    Context "What it must never delete" {

        It "leaves a file the application did not write" {
            $Foreign = Join-Path $Script:Folder -ChildPath "my-own-notes.log"
            Set-Content -Path $Foreign -Value "keep me" -Encoding UTF8
            (Get-Item $Foreign).LastWriteTime = [datetime]::Now.AddDays(-400)

            Remove-ExpiredSessionLogFile -Directory $Script:Folder -RetentionDays 1 -RetentionCount 1

            Test-Path $Foreign | Should -BeTrue
        }

        It "leaves the session that is starting right now, whatever the retention says" {
            $StartTime = [datetime]::Now.AddDays(-400)
            $Current = New-TestSessionLogFile -Folder $Script:Folder -StartTime $StartTime -ProcessId 401 -LastWriteTime $StartTime
            $SessionKey = "{0}_pid401" -f $StartTime.ToString("yyyyMMdd-HHmmss")

            Remove-ExpiredSessionLogFile -Directory $Script:Folder -RetentionDays 1 -RetentionCount 1 -ExcludeSession $SessionKey

            Test-Path $Current[0] | Should -BeTrue
        }
    }

    Context "A folder it cannot use" {

        It "does not throw when the folder does not exist" {
            { Remove-ExpiredSessionLogFile -Directory (Join-Path $Script:Folder -ChildPath "nope") -RetentionDays 14 -RetentionCount 20 } | Should -Not -Throw
        }
    }

    Context "Required parameters" {

        It "declares <Parameter> mandatory" -ForEach @(
            @{ Parameter = "Directory" }
            @{ Parameter = "RetentionDays" }
            @{ Parameter = "RetentionCount" }
        ) {
            (Get-Command Remove-ExpiredSessionLogFile).Parameters[$Parameter].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory } | Should -Contain $true
        }
    }
}
