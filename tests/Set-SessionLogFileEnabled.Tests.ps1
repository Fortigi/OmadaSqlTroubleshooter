#Requires -Version 7.0
# Tests for the log window's "Write log file" checkbox (issue #138).
#
# The checkbox is only worth having if it takes effect at once, so these run against a real folder
# with real handles: "the file is closed" is a statement about the operating system releasing a
# handle, and only a real rename can make it true or false.
#
# The sequence that matters most is off, on, off in one session. It has to leave one session's files
# in the folder - not a clobbered file, not a second session, and not a writer nobody closed.

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
    . (Join-Path $PrivatePath -ChildPath "Set-SessionLogFileEnabled.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:SchemaPath = Join-Path $ParentPath -ChildPath "src\Lib\schema\appGlobalConfigSchema.json"

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

    function Write-ContainedErrorLog {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            $ErrorObject
        )
        process {
            $Script:LoggedMessage.Add([PSCustomObject]@{ LogType = "ERROR"; Message = [string]$Message })
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

    # The real one writes the configuration file; what matters here is that the value lands on
    # $Script:AppGlobalConfig, because that is what Get-LogFileSetting reads back.
    function Set-ConfigProperty {
        param(
            [Parameter(ValueFromPipeline = $true, Position = 0)]$Value,
            [string]$Property,
            [string]$JoinString = " - ",
            [switch]$Reset
        )
        process {
            $Script:PersistedProperty.Add([PSCustomObject]@{ Property = $Property; Value = $Value })
            $Script:AppGlobalConfig.$Property = $Value
        }
    }

    # A handle this session still holds refuses a rename: the writer does not share Delete. So a
    # successful rename is proof the file was really closed.
    function Test-SessionLogFileClosed {
        param([string]$Path)

        $Probe = "{0}.probe" -f $Path
        try {
            [System.IO.File]::Move($Path, $Probe)
            [System.IO.File]::Move($Probe, $Path)
            return $true
        }
        catch {
            return $false
        }
    }
}

Describe "Set-SessionLogFileEnabled" {

    BeforeEach {
        $Script:AppDataFolder = Join-Path ([System.IO.Path]::GetTempPath()) -ChildPath ("OmadaSqlLogToggle_{0}" -f ([guid]::NewGuid().ToString("N")))
        [System.IO.Directory]::CreateDirectory($Script:AppDataFolder) | Out-Null
        $Script:LogFolder = Join-Path $Script:AppDataFolder -ChildPath "logs"
        $Script:RunTimeConfig = [PSCustomObject]@{
            ApplicationName = "Test"
            AppDataFolder   = $Script:AppDataFolder
        }
        # Off, as a fresh installation has it: the checkbox is what turns it on.
        $Script:AppGlobalConfig = [PSCustomObject]@{
            EnableSessionLogFile    = $false
            SessionLogFileDirectory = $null
        }
        $Script:SessionLogFile = New-SessionLogFileState -LogLevel "DEBUG"
        $Script:LoggedMessage = [System.Collections.Generic.List[PSCustomObject]]::new()
        $Script:PersistedProperty = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    AfterEach {
        Stop-SessionLogFile
        Remove-Item -LiteralPath $Script:AppDataFolder -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Ticking it" {

        It "opens a file there and then, without a restart" {
            $Writing = Set-SessionLogFileEnabled -Enabled $true

            $Writing | Should -BeTrue
            $Script:SessionLogFile.Path | Should -BeExactly (Join-Path $Script:LogFolder -ChildPath "OmadaSqlTroubleshooter.log")
            Test-Path -LiteralPath $Script:SessionLogFile.Path | Should -BeTrue
        }

        It "writes the lines logged from that moment on" {
            Set-SessionLogFileEnabled -Enabled $true | Out-Null

            Write-SessionLogFile -Line "logged after the box was ticked" -LogType "ERROR"

            Get-Content -LiteralPath $Script:SessionLogFile.Path -Raw | Should -Match "logged after the box was ticked"
        }

        It "persists the choice, which is what makes it apply at the next start" {
            Set-SessionLogFileEnabled -Enabled $true | Out-Null

            $Script:AppGlobalConfig.EnableSessionLogFile | Should -BeTrue
            ($Script:PersistedProperty | Where-Object { $_.Property -eq "EnableSessionLogFile" } | Measure-Object).Count | Should -Be 1
        }

        It "does nothing when a file is already being written" {
            # Open-LogForm reflects the resolved setting in the checkbox, so this must not rotate the
            # file the session is already writing just because the window was opened.
            Set-SessionLogFileEnabled -Enabled $true | Out-Null
            $Path = $Script:SessionLogFile.Path
            $Writer = $Script:SessionLogFile.Writer

            $Writing = Set-SessionLogFileEnabled -Enabled $true

            $Writing | Should -BeTrue
            $Script:SessionLogFile.Path | Should -BeExactly $Path
            [object]::ReferenceEquals($Script:SessionLogFile.Writer, $Writer) | Should -BeTrue
            (Get-ChildItem -LiteralPath $Script:LogFolder -File | Measure-Object).Count | Should -Be 1
        }
    }

    Context "Unticking it" {

        It "closes the file, releasing the handle" {
            Set-SessionLogFileEnabled -Enabled $true | Out-Null
            $Path = $Script:SessionLogFile.Path

            $Writing = Set-SessionLogFileEnabled -Enabled $false

            $Writing | Should -BeFalse
            Test-SessionLogFileClosed -Path $Path | Should -BeTrue
        }

        It "stops writing: a line logged afterwards is not in the file" {
            Set-SessionLogFileEnabled -Enabled $true | Out-Null
            $Path = $Script:SessionLogFile.Path

            Set-SessionLogFileEnabled -Enabled $false | Out-Null
            Write-SessionLogFile -Line "logged after the box was unticked" -LogType "ERROR"

            Get-Content -LiteralPath $Path -Raw | Should -Not -Match "logged after the box was unticked"
        }

        It "leaves the window with nothing to point at, rather than a path that is no longer written" {
            Set-SessionLogFileEnabled -Enabled $true | Out-Null

            Set-SessionLogFileEnabled -Enabled $false | Out-Null

            $Script:SessionLogFile.Path | Should -BeNullOrEmpty
            $Script:SessionLogFile.Directory | Should -BeNullOrEmpty
        }

        It "persists the choice" {
            Set-SessionLogFileEnabled -Enabled $true | Out-Null

            Set-SessionLogFileEnabled -Enabled $false | Out-Null

            $Script:AppGlobalConfig.EnableSessionLogFile | Should -BeFalse
        }

        It "does nothing when no file was being written" {
            { Set-SessionLogFileEnabled -Enabled $false | Out-Null } | Should -Not -Throw

            Test-Path -LiteralPath $Script:LogFolder | Should -BeFalse
        }
    }

    Context "Off, on and off again in one session" {

        It "continues the same session, keeping what was written before" {
            Set-SessionLogFileEnabled -Enabled $true | Out-Null
            $SessionKey = $Script:SessionLogFile.SessionKey
            Write-SessionLogFile -Line "from before the box was unticked" -LogType "ERROR"
            Set-SessionLogFileEnabled -Enabled $false | Out-Null

            Set-SessionLogFileEnabled -Enabled $true | Out-Null
            Write-SessionLogFile -Line "from after it was ticked again" -LogType "ERROR"

            $Script:SessionLogFile.SessionKey | Should -BeExactly $SessionKey
            $Rotated = Join-Path $Script:LogFolder -ChildPath (Get-SessionLogFileName -SessionKey $SessionKey -Part 1)
            Get-Content -LiteralPath $Rotated -Raw | Should -Match "from before the box was unticked"
            Get-Content -LiteralPath $Script:SessionLogFile.Path -Raw | Should -Match "from after it was ticked again"
            Get-Content -LiteralPath $Script:SessionLogFile.Path -Raw | Should -Not -Match "from before the box was unticked"
        }

        It "clobbers nothing: every part of the session is still there" {
            Set-SessionLogFileEnabled -Enabled $true | Out-Null
            Write-SessionLogFile -Line "first" -LogType "ERROR"
            Set-SessionLogFileEnabled -Enabled $false | Out-Null
            Set-SessionLogFileEnabled -Enabled $true | Out-Null
            Write-SessionLogFile -Line "second" -LogType "ERROR"

            (Get-ChildItem -LiteralPath $Script:LogFolder -File | Measure-Object).Count | Should -Be 2
        }

        It "leaks no handle: the last file is closed when the box is unticked again" {
            Set-SessionLogFileEnabled -Enabled $true | Out-Null
            Set-SessionLogFileEnabled -Enabled $false | Out-Null
            Set-SessionLogFileEnabled -Enabled $true | Out-Null
            $Path = $Script:SessionLogFile.Path

            Set-SessionLogFileEnabled -Enabled $false | Out-Null

            Test-SessionLogFileClosed -Path $Path | Should -BeTrue
        }

        It "does it without an error, however often it is toggled" {
            {
                foreach ($Round in 1..3) {
                    Set-SessionLogFileEnabled -Enabled $true | Out-Null
                    Set-SessionLogFileEnabled -Enabled $false | Out-Null
                }
            } | Should -Not -Throw

            ($Script:LoggedMessage | Where-Object { $_.LogType -eq "ERROR" } | Measure-Object).Count | Should -Be 0
        }
    }

    Context "A file it cannot open" {

        BeforeEach {
            # A file where the folder should be: the directory can never be created.
            $Blocked = Join-Path $Script:AppDataFolder -ChildPath "blocked"
            [System.IO.File]::WriteAllText($Blocked, "not a folder")
            $Script:AppGlobalConfig.SessionLogFileDirectory = Join-Path $Blocked -ChildPath "logs"
        }

        It "reports that nothing is being written, rather than claiming a file" {
            $Writing = Set-SessionLogFileEnabled -Enabled $true

            $Writing | Should -BeFalse
            $Script:SessionLogFile | Should -BeNullOrEmpty
        }

        It "says so once, with the warning the start-up path already writes" {
            Set-SessionLogFileEnabled -Enabled $true | Out-Null

            ($Script:LoggedMessage | Where-Object { $_.LogType -eq "WARNING" } | Measure-Object).Count | Should -Be 1
        }

        It "keeps the choice, so the next start tries again" {
            # The folder may be fixable, and a checkbox that silently switched itself off would hide
            # both the problem and the intent.
            Set-SessionLogFileEnabled -Enabled $true | Out-Null

            $Script:AppGlobalConfig.EnableSessionLogFile | Should -BeTrue
        }
    }

    Context "The next start" {

        It "writes a file when the box was left ticked" {
            Set-SessionLogFileEnabled -Enabled $true | Out-Null
            Stop-SessionLogFile
            $Script:SessionLogFile = New-SessionLogFileState -LogLevel "DEBUG"

            Start-SessionLogFile | Should -Not -BeNullOrEmpty
        }

        It "writes none when the box was left unticked" {
            Set-SessionLogFileEnabled -Enabled $true | Out-Null
            Set-SessionLogFileEnabled -Enabled $false | Out-Null
            $Script:SessionLogFile = New-SessionLogFileState -LogLevel "DEBUG"

            Start-SessionLogFile | Should -BeNullOrEmpty
            $Script:SessionLogFile | Should -BeNullOrEmpty
        }
    }
}
