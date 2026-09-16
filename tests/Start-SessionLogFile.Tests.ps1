#Requires -Version 7.0
# Tests for starting the session log file (issue #121, as the maintainer revised it).
#
# Start-up decides whether a file is written at all - off unless configured - where it goes, what it
# is called, what happens to the previous session's file and to another instance's live one, which
# held lines reach it, and what is pruned. All of that is asserted against a real folder.
#
# The last context keeps the feature honest: a log file the application cannot open must never be
# the reason the application does not start.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Resolve-StrictBoolean.ps1")
    . (Join-Path $PrivatePath -ChildPath "Resolve-LogLevel.ps1")
    . (Join-Path $PrivatePath -ChildPath "Test-LogLevelThreshold.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SessionLogFileName.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-LogFileSetting.ps1")
    . (Join-Path $PrivatePath -ChildPath "Remove-ExcessSessionLogFile.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-SessionLogFile.ps1")
    . (Join-Path $PrivatePath -ChildPath "Open-SessionLogFile.ps1")
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
        [System.IO.Directory]::CreateDirectory($Script:AppDataFolder) | Out-Null
        $Script:LogFolder = Join-Path $Script:AppDataFolder -ChildPath "logs"
        $Script:RunTimeConfig = [PSCustomObject]@{
            ApplicationName = "Test"
            AppDataFolder   = $Script:AppDataFolder
        }
        $Script:AppGlobalConfig = [PSCustomObject]@{ EnableSessionLogFile = $true }
        $Script:SessionLogFile = New-SessionLogFileState -LogLevel "DEBUG"
        $Script:LoggedMessage = [System.Collections.Generic.List[PSCustomObject]]::new()
        $Script:OtherInstance = $null
    }

    AfterEach {
        Stop-SessionLogFile
        if ($null -ne $Script:OtherInstance -and $null -ne $Script:OtherInstance.Writer) {
            $Script:OtherInstance.Writer.Dispose()
        }

        Remove-Item -LiteralPath $Script:AppDataFolder -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Off by default" {

        It "creates no folder and no file when nothing is configured" {
            $Script:AppGlobalConfig = $null

            Start-SessionLogFile | Should -BeNullOrEmpty

            $Script:SessionLogFile | Should -BeNullOrEmpty
            Test-Path -LiteralPath $Script:LogFolder | Should -BeFalse
        }

        It "creates nothing when switched off explicitly" {
            $Script:AppGlobalConfig = [PSCustomObject]@{ EnableSessionLogFile = $false }

            Start-SessionLogFile | Out-Null

            $Script:SessionLogFile | Should -BeNullOrEmpty
            Test-Path -LiteralPath $Script:LogFolder | Should -BeFalse
        }
    }

    Context "Switched on" {

        It "writes OmadaSqlTroubleshooter.log under the application's own per-user folder" {
            $Path = Start-SessionLogFile

            $Path | Should -BeExactly (Join-Path $Script:LogFolder -ChildPath "OmadaSqlTroubleshooter.log")
            Test-Path -LiteralPath $Path | Should -BeTrue
        }

        It "leaves the state ready to be written to, at the configured level and a 5 MB split size" {
            Start-SessionLogFile | Out-Null

            $Script:SessionLogFile.Writer | Should -Not -BeNullOrEmpty
            $Script:SessionLogFile.LogLevel | Should -BeExactly "DEBUG"
            $Script:SessionLogFile.MaxBytes | Should -Be (5 * 1MB)
            $Script:SessionLogFile.UsesActiveName | Should -BeTrue
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

        It "treats SessionLogFileDirectory as a literal path, brackets and all" {
            $Bracketed = Join-Path $Script:AppDataFolder -ChildPath "logs[1]"
            $Script:AppGlobalConfig = [PSCustomObject]@{
                EnableSessionLogFile    = $true
                SessionLogFileDirectory = $Bracketed
            }

            $Path = Start-SessionLogFile
            Write-SessionLogFile -Line "into a bracketed folder" -LogType "ERROR"

            (Split-Path $Path -Parent) | Should -BeExactly $Bracketed
            Get-Content -LiteralPath $Path -Raw | Should -Match "into a bracketed folder"
        }
    }

    Context "The previous session's file and another instance's" {

        It "renames what a closed previous session left and starts a fresh OmadaSqlTroubleshooter.log" {
            Start-SessionLogFile | Out-Null
            Write-SessionLogFile -Line "from the first session" -LogType "ERROR"
            $FirstKey = $Script:SessionLogFile.SessionKey
            Stop-SessionLogFile
            $Script:SessionLogFile = New-SessionLogFileState -LogLevel "DEBUG"

            $Path = Start-SessionLogFile

            $Rotated = Join-Path $Script:LogFolder -ChildPath (Get-SessionLogFileName -SessionKey $FirstKey -Part 1)
            Get-Content -LiteralPath $Rotated -Raw | Should -Match "from the first session"
            $Path | Should -BeExactly (Join-Path $Script:LogFolder -ChildPath "OmadaSqlTroubleshooter.log")
            Get-Content -LiteralPath $Path -Raw | Should -Not -Match "from the first session"
            $Script:SessionLogFile.SessionKey | Should -Not -BeExactly $FirstKey
        }

        It "writes its own numbered file while another instance holds OmadaSqlTroubleshooter.log" {
            Start-SessionLogFile | Out-Null
            Write-SessionLogFile -Line "the first instance is running" -LogType "ERROR"
            $Script:OtherInstance = $Script:SessionLogFile
            $Script:SessionLogFile = New-SessionLogFileState -LogLevel "DEBUG"

            $Path = Start-SessionLogFile

            (Split-Path $Path -Leaf) | Should -BeExactly (Get-SessionLogFileName -SessionKey $Script:SessionLogFile.SessionKey -Part 1)
            $Script:SessionLogFile.UsesActiveName | Should -BeFalse
            $Script:SessionLogFile.SessionKey | Should -Not -BeExactly $Script:OtherInstance.SessionKey
            Test-Path -LiteralPath $Script:OtherInstance.Path | Should -BeTrue
            ($Script:LoggedMessage | Where-Object { $_.LogType -eq "INFO" -and $_.Message -match "in use" } | Measure-Object).Count | Should -Be 1
        }
    }

    Context "Resuming a session the checkbox switched off (issue #138)" {

        It "keeps the session key, so one application session stays one session in the folder" {
            Start-SessionLogFile | Out-Null
            $SessionKey = $Script:SessionLogFile.SessionKey
            Write-SessionLogFile -Line "before the checkbox was unticked" -LogType "ERROR"
            Stop-SessionLogFile

            $Path = Start-SessionLogFile

            $Script:SessionLogFile.SessionKey | Should -BeExactly $SessionKey
            $Path | Should -BeExactly (Join-Path $Script:LogFolder -ChildPath "OmadaSqlTroubleshooter.log")
            $Rotated = Join-Path $Script:LogFolder -ChildPath (Get-SessionLogFileName -SessionKey $SessionKey -Part 1)
            Get-Content -LiteralPath $Rotated -Raw | Should -Match "before the checkbox was unticked"
            Get-Content -LiteralPath $Path -Raw | Should -Not -Match "before the checkbox was unticked"
        }

        It "clears the failure flag, so lines actually reach the file it just opened" {
            # A write that failed earlier disabled the file for the rest of the session. Reopening it
            # deliberately has to lift that, or the checkbox would report a file nothing is written to.
            Start-SessionLogFile | Out-Null
            Stop-SessionLogFile
            $Script:SessionLogFile.Failed = $true

            $Path = Start-SessionLogFile
            Write-SessionLogFile -Line "after the checkbox was ticked again" -LogType "ERROR"

            $Script:SessionLogFile.Failed | Should -BeFalse
            Get-Content -LiteralPath $Path -Raw | Should -Match "after the checkbox was ticked again"
        }
    }

    Context "Retention" {

        It "keeps at most ten sessions by default, the one starting included" {
            [System.IO.Directory]::CreateDirectory($Script:LogFolder) | Out-Null
            foreach ($Day in 1..12) {
                $SessionKey = "202601{0:00}-080000" -f $Day
                $Opened = Open-SessionLogFileWriter -Path (Join-Path $Script:LogFolder -ChildPath (Get-SessionLogFileName -SessionKey $SessionKey -Part 1)) -SessionKey $SessionKey -StartTime ([datetime]::new(2026, 1, $Day, 8, 0, 0)) -ProcessId 4242
                $Opened.Writer.Dispose()
            }

            Start-SessionLogFile | Out-Null

            $SessionKey = @(Get-SessionLogFileInventory -Directory $Script:LogFolder | ForEach-Object {
                    if ($_.IsActive) {
                        (Read-SessionLogFileHeader -Path $_.Path).SessionKey
                    }
                    else {
                        $_.SessionKey
                    }
                } | Sort-Object -Unique)
            $SessionKey.Count | Should -Be 10
            $SessionKey | Should -Contain $Script:SessionLogFile.SessionKey
            $SessionKey | Should -Not -Contain "20260101-080000"
            $SessionKey | Should -Not -Contain "20260102-080000"
            $SessionKey | Should -Not -Contain "20260103-080000"
        }
    }

    Context "A file it cannot open" {

        BeforeEach {
            # A file where the folder should be: the directory can never be created.
            $Blocked = Join-Path $Script:AppDataFolder -ChildPath "blocked"
            [System.IO.File]::WriteAllText($Blocked, "not a folder")
            $Script:AppGlobalConfig = [PSCustomObject]@{
                EnableSessionLogFile    = $true
                SessionLogFileDirectory = (Join-Path $Blocked -ChildPath "logs")
            }
        }

        It "starts the application anyway, with no file and no exception" {
            { Start-SessionLogFile | Out-Null } | Should -Not -Throw

            $Script:SessionLogFile | Should -BeNullOrEmpty
        }

        It "says so once, without a dialog" {
            Start-SessionLogFile | Out-Null

            ($Script:LoggedMessage | Where-Object { $_.LogType -eq "WARNING" } | Measure-Object).Count | Should -Be 1
        }

        It "leaves a later write harmless" {
            Start-SessionLogFile | Out-Null

            { Write-SessionLogFile -Line "nowhere to go" -LogType "ERROR" } | Should -Not -Throw
        }
    }
}
