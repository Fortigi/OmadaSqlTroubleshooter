BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $FunctionPath = Join-Path $ParentPath -ChildPath "src\lib\functions\Private"
    . (Join-Path $FunctionPath -ChildPath "Initialize-GlobalConfigSettings.ps1")
    . (Join-Path $FunctionPath -ChildPath "Resolve-LogLevel.ps1")
    . (Join-Path $FunctionPath -ChildPath "Get-ConfigSchemaDefault.ps1")
    # The tracer preamble of the functions under test redacts their bound parameters.
    . (Join-Path $FunctionPath -ChildPath "ConvertTo-RedactedLogString.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:ModuleSourceFolder = Join-Path $ParentPath -ChildPath "src"

    # Stand-ins for the ambient application state Initialize-GlobalConfigSettings reaches into.
    # They are deliberately plain functions rather than Pester mocks: Set-ConfigProperty takes
    # pipeline input and has to mutate the simulated config file, which is easier to reason about
    # here than mock parameter filters.
    function Write-LogOutput {
        param(
            [parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
            [string]$Message,
            $ErrorObject,
            [string]$LogType = "INFO",
            [switch]$SkipDialog
        )
    }

    function Get-ModuleBaseFolder {
        return $Script:ModuleSourceFolder
    }

    # The single writer of the "show request body" state (issue #62). Recorded rather than executed,
    # so these tests stay about log level resolution while still proving the state is resolved here.
    function Set-BodyRedactionState {
        param(
            [Parameter(Mandatory = $true, Position = 0)]
            [bool]$Enabled
        )
        $Script:BodyRedactionStateCalls.Add($Enabled)
    }

    function Get-FormPositionConfig {
        param(
            [parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
            $Definition
        )
        # Non-null keeps Initialize-GlobalConfigSettings out of the WPF branch, which cannot be
        # resolved on a headless test agent.
        return "100x100"
    }

    function Set-ConfigProperty {
        param(
            [parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
            $Value,
            [parameter(Mandatory = $false)]
            [string]$Property,
            [string]$JoinString = " - ",
            [switch]$Reset
        )
        process {
            if ($Reset) {
                $Script:AppGlobalConfig = $null
                return
            }

            if ([string]::IsNullOrWhiteSpace($Property)) {
                return
            }

            $Script:ConfigWrites.Add([PSCustomObject]@{ Property = $Property; Value = $Value })
            if ($null -ne $Script:AppGlobalConfig) {
                $Script:AppGlobalConfig.$Property = $Value
            }
        }
    }

    function New-PersistedConfig {
        param(
            $LogLevel
        )
        return [PSCustomObject]@{
            LogLevel           = $LogLevel
            CheckboxConsoleLog = $false
            InstanceGuid       = "11111111111111111111111111111111"
        }
    }

    function New-RuntimeConfig {
        param(
            $LogLevelSetting,
            [bool]$LogLevelExplicit,
            [bool]$SkipBodyRedaction
        )
        return [PSCustomObject]@{
            ApplicationName = "Test"
            InstanceGuid    = "11111111111111111111111111111111"
            Logging         = [PSCustomObject]@{
                LogToConsole      = $false
                LogLevel          = $null
                LogLevelSetting   = $LogLevelSetting
                LogLevelExplicit  = $LogLevelExplicit
                SkipBodyRedaction = $SkipBodyRedaction
            }
        }
    }
}

Describe 'Initialize-GlobalConfigSettings log level resolution' {

    BeforeEach {
        $Script:ConfigWrites = [System.Collections.Generic.List[object]]::new()
        $Script:BodyRedactionStateCalls = [System.Collections.Generic.List[object]]::new()
        $Script:MainForm = $null
        $Script:GlobalConfigProperties = $null
    }

    Context 'A level was chosen in the log viewer during an earlier session' {

        BeforeEach {
            $Script:AppGlobalConfig = New-PersistedConfig -LogLevel "DEBUG"
            $Script:RunTimeConfig = New-RuntimeConfig -LogLevelSetting "WARNING" -LogLevelExplicit $false
            Initialize-GlobalConfigSettings
        }

        It 'restores the persisted level into the runtime configuration' {
            $Script:RunTimeConfig.Logging.LogLevel | Should -BeExactly "DEBUG"
        }

        It 'applies the persisted level to the level that actually filters log output' {
            $Script:RunTimeConfig.Logging.LogLevelSetting | Should -BeExactly "DEBUG"
        }

        It 'does not overwrite the persisted level in the config file' {
            $Script:ConfigWrites | Where-Object { $_.Property -eq "LogLevel" } | Should -BeNullOrEmpty
            $Script:AppGlobalConfig.LogLevel | Should -BeExactly "DEBUG"
        }
    }

    Context 'An explicit -LogLevel parameter was supplied' {

        BeforeEach {
            $Script:AppGlobalConfig = New-PersistedConfig -LogLevel "DEBUG"
            $Script:RunTimeConfig = New-RuntimeConfig -LogLevelSetting "ERROR" -LogLevelExplicit $true
            Initialize-GlobalConfigSettings
        }

        It 'wins over the persisted level' {
            $Script:RunTimeConfig.Logging.LogLevel | Should -BeExactly "ERROR"
            $Script:RunTimeConfig.Logging.LogLevelSetting | Should -BeExactly "ERROR"
        }

        It 'is written back so it also becomes the level for the next session' {
            $Write = $Script:ConfigWrites | Where-Object { $_.Property -eq "LogLevel" }
            $Write | Should -Not -BeNullOrEmpty
            $Write.Value | Should -BeExactly "ERROR"
        }
    }

    Context 'Nothing has been persisted yet' {

        BeforeEach {
            $Script:AppGlobalConfig = New-PersistedConfig -LogLevel $null
            $Script:RunTimeConfig = New-RuntimeConfig -LogLevelSetting "WARNING" -LogLevelExplicit $false
            Initialize-GlobalConfigSettings
        }

        It 'falls back to the schema default' {
            $Script:RunTimeConfig.Logging.LogLevel | Should -BeExactly "WARNING"
            $Script:RunTimeConfig.Logging.LogLevelSetting | Should -BeExactly "WARNING"
        }

        It 'seeds the config file with the schema default' {
            $Write = $Script:ConfigWrites | Where-Object { $_.Property -eq "LogLevel" }
            $Write | Should -Not -BeNullOrEmpty
            $Write.Value | Should -BeExactly "WARNING"
        }
    }

    Context 'The persisted value is not a level the application knows' {

        BeforeEach {
            $Script:AppGlobalConfig = New-PersistedConfig -LogLevel "NOT_A_LEVEL"
            $Script:RunTimeConfig = New-RuntimeConfig -LogLevelSetting "WARNING" -LogLevelExplicit $false
            Initialize-GlobalConfigSettings
        }

        It 'falls back to the schema default instead of throwing' {
            $Script:RunTimeConfig.Logging.LogLevelSetting | Should -BeExactly "WARNING"
        }

        It 'repairs the stored value' {
            $Script:AppGlobalConfig.LogLevel | Should -BeExactly "WARNING"
        }
    }

    Context 'The persisted value is usable but not normalized' {

        BeforeEach {
            $Script:AppGlobalConfig = New-PersistedConfig -LogLevel " debug "
            $Script:RunTimeConfig = New-RuntimeConfig -LogLevelSetting "WARNING" -LogLevelExplicit $false
            Initialize-GlobalConfigSettings
        }

        It 'still honours the level the user chose' {
            $Script:RunTimeConfig.Logging.LogLevelSetting | Should -BeExactly "DEBUG"
        }

        It 'normalizes the stored value once' {
            $Script:AppGlobalConfig.LogLevel | Should -BeExactly "DEBUG"
        }

        It 'leaves the normalized value alone on the next start' {
            $Script:ConfigWrites = [System.Collections.Generic.List[object]]::new()
            $Script:AppGlobalConfig = New-PersistedConfig -LogLevel "DEBUG"
            $Script:RunTimeConfig = New-RuntimeConfig -LogLevelSetting "WARNING" -LogLevelExplicit $false
            Initialize-GlobalConfigSettings

            $Script:ConfigWrites | Where-Object { $_.Property -eq "LogLevel" } | Should -BeNullOrEmpty
        }
    }

    Context 'Round trip across a restart' {

        It 'keeps the level chosen in the log viewer, and leaves the stored value untouched' {
            # Session one: the user picks VERBOSE in the log viewer, which stores it.
            $Script:AppGlobalConfig = New-PersistedConfig -LogLevel $null
            $Script:RunTimeConfig = New-RuntimeConfig -LogLevelSetting "WARNING" -LogLevelExplicit $false
            Initialize-GlobalConfigSettings
            "VERBOSE" | Set-ConfigProperty -Property "LogLevel"

            $PersistedAfterFirstSession = $Script:AppGlobalConfig.LogLevel
            $PersistedAfterFirstSession | Should -BeExactly "VERBOSE"

            # Session two: a fresh start with no -LogLevel parameter reads the same config back.
            $Script:ConfigWrites = [System.Collections.Generic.List[object]]::new()
            $Script:AppGlobalConfig = New-PersistedConfig -LogLevel $PersistedAfterFirstSession
            $Script:RunTimeConfig = New-RuntimeConfig -LogLevelSetting "WARNING" -LogLevelExplicit $false
            Initialize-GlobalConfigSettings

            $Script:RunTimeConfig.Logging.LogLevelSetting | Should -BeExactly "VERBOSE"
            $Script:AppGlobalConfig.LogLevel | Should -BeExactly "VERBOSE"
            $Script:ConfigWrites | Where-Object { $_.Property -eq "LogLevel" } | Should -BeNullOrEmpty
        }
    }
}

Describe 'Invoke-OmadaSqlTroubleshooter log level seeding' {

    BeforeAll {
        $ParentPath = Split-Path -Path $PSScriptRoot -Parent
        $Script:EntryPointSource = Get-Content (Join-Path $ParentPath -ChildPath "src\lib\functions\Public\Invoke-OmadaSqlTroubleshooter.ps1") -Raw
    }

    It 'does not hardcode a log level default any more' {
        $Script:EntryPointSource | Should -Not -Match 'IsNullOrWhiteSpace\(\$LogLevel\)\)\s*\{\s*"WARNING"'
    }

    It 'records whether -LogLevel was explicitly bound' {
        $Script:EntryPointSource | Should -Match 'BoundParameters\.ContainsKey\("LogLevel"\)'
    }

    It 'seeds the runtime level through the shared resolver' {
        $Script:EntryPointSource | Should -Match 'Resolve-LogLevel'
    }
}

Describe 'Initialize-GlobalConfigSettings show request body resolution' {

    BeforeEach {
        $Script:ConfigWrites = [System.Collections.Generic.List[object]]::new()
        $Script:BodyRedactionStateCalls = [System.Collections.Generic.List[object]]::new()
        $Script:MainForm = $null
        $Script:GlobalConfigProperties = $null
        $Script:AppGlobalConfig = New-PersistedConfig -LogLevel "DEBUG"
    }

    It 'leaves the option off when neither the parameter nor the stored setting asks for it' {
        $Script:RunTimeConfig = New-RuntimeConfig -LogLevelSetting "WARNING" -LogLevelExplicit $false -SkipBodyRedaction $false

        Initialize-GlobalConfigSettings

        $Script:BodyRedactionStateCalls | Should -Contain $false
        $Script:BodyRedactionStateCalls | Should -Not -Contain $true
    }

    It 'turns the option on for -SkipBodyRedaction, before the first request' {
        $Script:RunTimeConfig = New-RuntimeConfig -LogLevelSetting "WARNING" -LogLevelExplicit $false -SkipBodyRedaction $true

        Initialize-GlobalConfigSettings

        $Script:BodyRedactionStateCalls | Should -Contain $true
        # ...and stored, so the log viewer opens with the checkbox already checked.
        ($Script:ConfigWrites | Where-Object { $_.Property -eq "SkipBodyRedaction" }).Value | Should -BeTrue
    }

    It 'restores the option a previous session stored' {
        $Script:AppGlobalConfig | Add-Member -NotePropertyName "SkipBodyRedaction" -NotePropertyValue $true -Force
        $Script:RunTimeConfig = New-RuntimeConfig -LogLevelSetting "WARNING" -LogLevelExplicit $false -SkipBodyRedaction $false

        Initialize-GlobalConfigSettings

        $Script:BodyRedactionStateCalls | Should -Contain $true
    }
}
