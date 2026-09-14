#Requires -Version 7.0
# Tests for starting the session log file (issue #121).
#
# Start-up is where the feature either delivers or does not: it decides whether a file is written at
# all, where it goes, what it is called, which of the lines already emitted reach it, and what is
# pruned before it opens. All of that is asserted against a real folder.
#
# The last context is the one that keeps the feature honest. A log file the application cannot open
# must never be the reason the application does not start.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Resolve-StrictBoolean.ps1")
    . (Join-Path $PrivatePath -ChildPath "Resolve-LogLevel.ps1")
    . (Join-Path $PrivatePath -ChildPath "Test-LogLevelThreshold.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SessionLogFileName.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-LogFileSetting.ps1")
    . (Join-Path $PrivatePath -ChildPath "Remove-ExpiredSessionLogFile.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-SessionLogFile.ps1")
    . (Join-Path $PrivatePath -ChildPath "Start-SessionLogFile.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:SchemaPath = Join-Path $ParentPath -ChildPath "src\Lib\schema\appGlobalConfigSchema.json"

    # Captures what the start-up path reports, so the "it could not open the file" case can be
    # asserted on rather than assumed.
    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType = "INFO",
            $ErrorObject,
            [switch]$SkipDialog
        )
        process {
            $Script:LoggedMessage.Add([PSCustomObject]@{ LogType = $LogType; Message = [string]$Message })
        }
    }

    function ConvertTo-RedactedLogString {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [int]$MaxDepth = 6)
        process { return "" }
    }

    function Get-ConfigSchemaDefault {
        param(
            [Parameter(Mandatory = $true, Position = 0)]
            [string]$Property,
            [string]$SchemaPath
        )

        $Definition = Get-Content $Script:SchemaPath -Raw | ConvertFrom-Json | Where-Object { $_.Name -eq $Property } | Select-Object -First 1
        if ($null -eq $Definition) {
            return $null
        }

        return $Definition.DefaultValue
    }
}

Describe "Start-SessionLogFile" {

    BeforeEach {
        $Script:AppDataFolder = Join-Path ([System.IO.Path]::GetTempPath()) -ChildPath ("OmadaSqlLogStart_{0}" -f ([guid]::NewGuid().ToString("N")))
        New-Item -Path $Script:AppDataFolder -ItemType Directory -Force | Out-Null
        $Script:RunTimeConfig = [PSCustomObject]@{
            ApplicationName = "Test"
            AppDataFolder   = $Script:AppDataFolder
        }
        $Script:AppGlobalConfig = $null
        $Script:SessionLogFile = New-SessionLogFileState -LogLevel "DEBUG"
        $Script:LoggedMessage = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    AfterEach {
        Stop-SessionLogFile
        Remove-Item -Path $Script:AppDataFolder -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "On by default" {

        It "creates a file under the application's own per-user folder" {
            $Path = Start-SessionLogFile

            $Path | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath $Path | Should -BeTrue
            (Split-Path $Path -Parent) | Should -BeExactly (Join-Path $Script:AppDataFolder -ChildPath "logs")
        }

        It "names the file for the session that is starting" {
            $Path = Start-SessionLogFile

            (Split-Path $Path -Leaf) | Should -Match (Get-SessionLogFileNameExpression)
            (Split-Path $Path -Leaf) | Should -Match ("pid{0}_" -f $PID)
        }

        It "leaves the state ready to be written to, at the configured level and ceiling" {
            Start-SessionLogFile | Out-Null

            $Script:SessionLogFile.Writer | Should -Not -BeNullOrEmpty
            $Script:SessionLogFile.LogLevel | Should -BeExactly "DEBUG"
            $Script:SessionLogFile.MaxBytes | Should -Be (20 * 1MB)
        }

        It "writes the lines that were emitted before it opened" {
            Write-SessionLogFile -Line "something failed during start-up" -LogType "ERROR"

            $Path = Start-SessionLogFile

            Get-Content -LiteralPath $Path -Raw | Should -Match "something failed during start-up"
        }

        It "says where the file is, so the path is discoverable from the log" {
            $Path = Start-SessionLogFile

            ($Script:LoggedMessage | Where-Object { $_.Message -like ("*{0}*" -f $Path) } | Measure-Object).Count | Should -BeGreaterThan 0
        }
    }

    Context "A configured directory PowerShell might read as a pattern" {

        It "treats SessionLogFileDirectory as a literal path, brackets and all" {
            # SessionLogFileDirectory is whatever the user typed, and "[" and "]" are wildcard
            # characters to most of PowerShell's path parameters. A real folder called "logs[1]" must
            # be created and written to, not pattern-matched against.
            $Bracketed = Join-Path $Script:AppDataFolder -ChildPath "logs[1]"
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileDirectory = $Bracketed }

            $Path = Start-SessionLogFile
            Write-SessionLogFile -Line "into a bracketed folder" -LogType "ERROR"

            Test-Path -LiteralPath $Bracketed -PathType Container | Should -BeTrue
            (Split-Path $Path -Parent) | Should -BeExactly $Bracketed
            Get-Content -LiteralPath $Path -Raw | Should -Match "into a bracketed folder"
        }
    }

    Context "Switched off" {

        It "writes no file and leaves nothing to write to" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ EnableSessionLogFile = $false }

            Start-SessionLogFile | Out-Null

            $Script:SessionLogFile | Should -BeNullOrEmpty
            Test-Path -LiteralPath (Join-Path $Script:AppDataFolder -ChildPath "logs") | Should -BeFalse
        }
    }

    Context "Pruning happens before the file is opened" {

        It "removes an expired session from a previous run" {
            $LogFolder = Join-Path $Script:AppDataFolder -ChildPath "logs"
            New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
            $Stale = Join-Path $LogFolder -ChildPath (Get-SessionLogFileName -StartTime ([datetime]::Now.AddDays(-90)) -ProcessId 999 -Part 1)
            Set-Content -Path $Stale -Value "old" -Encoding UTF8
            (Get-Item $Stale).LastWriteTime = [datetime]::Now.AddDays(-90)

            Start-SessionLogFile | Out-Null

            Test-Path -LiteralPath $Stale | Should -BeFalse
        }

        It "does not prune the session it is about to write" {
            $Script:AppGlobalConfig = [PSCustomObject]@{
                SessionLogFileRetentionDays  = 1
                SessionLogFileRetentionCount = 1
            }

            $Path = Start-SessionLogFile
            Write-SessionLogFile -Line "still here" -LogType "ERROR"

            Test-Path -LiteralPath $Path | Should -BeTrue
        }
    }

    Context "A file it cannot open" {

        It "starts the application anyway, with no file and no exception" {
            # A file where the folder should be: the directory can never be created.
            $Blocked = Join-Path $Script:AppDataFolder -ChildPath "blocked"
            Set-Content -Path $Blocked -Value "not a folder" -Encoding UTF8
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileDirectory = (Join-Path $Blocked -ChildPath "logs") }

            { Start-SessionLogFile | Out-Null } | Should -Not -Throw

            $Script:SessionLogFile | Should -BeNullOrEmpty
        }

        It "says so once, without a dialog" {
            $Blocked = Join-Path $Script:AppDataFolder -ChildPath "blocked"
            Set-Content -Path $Blocked -Value "not a folder" -Encoding UTF8
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileDirectory = (Join-Path $Blocked -ChildPath "logs") }

            Start-SessionLogFile | Out-Null

            ($Script:LoggedMessage | Where-Object { $_.LogType -eq "WARNING" } | Measure-Object).Count | Should -Be 1
        }

        It "leaves a later write harmless" {
            $Blocked = Join-Path $Script:AppDataFolder -ChildPath "blocked"
            Set-Content -Path $Blocked -Value "not a folder" -Encoding UTF8
            $Script:AppGlobalConfig = [PSCustomObject]@{ SessionLogFileDirectory = (Join-Path $Blocked -ChildPath "logs") }
            Start-SessionLogFile | Out-Null

            { Write-SessionLogFile -Line "nowhere to go" -LogType "ERROR" } | Should -Not -Throw
        }
    }
}
