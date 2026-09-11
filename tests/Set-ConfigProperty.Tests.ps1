BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $FunctionPath = Join-Path $ParentPath -ChildPath "src\lib\functions\Private"
    . (Join-Path $FunctionPath -ChildPath "Set-ConfigProperty.ps1")
    . (Join-Path $FunctionPath -ChildPath "Add-ConfigProperty.ps1")
    # The tracer preamble of the functions under test redacts their bound parameters.
    . (Join-Path $FunctionPath -ChildPath "ConvertTo-RedactedLogString.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:ModuleSourceFolder = Join-Path $ParentPath -ChildPath "src"

    # The real schema files are the point of these tests: reconciliation has to be driven by what
    # is actually shipped, not by a fixture that could drift away from it.
    $Script:GlobalSchema = Get-Content (Join-Path $Script:ModuleSourceFolder -ChildPath "lib\schema\appGlobalConfigSchema.json") -Raw | ConvertFrom-Json
    $Script:TabSchema = Get-Content (Join-Path $Script:ModuleSourceFolder -ChildPath "lib\schema\appConfigSchema.json") -Raw | ConvertFrom-Json

    $Script:LogMessages = [System.Collections.Generic.List[string]]::new()

    function Write-LogOutput {
        param(
            [parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
            [string]$Message,
            $ErrorObject,
            [string]$LogType = "INFO",
            [switch]$SkipDialog,
            [switch]$TabScoped
        )
        process { $Script:LogMessages.Add(("{0}: {1}" -f $LogType, $Message)) }
    }

    function Get-ModuleBaseFolder {
        return $Script:ModuleSourceFolder
    }

    function Get-ActiveTabSession {
        return $Script:StubActiveTab
    }

    # Each test gets its own config file and a clean schema cache, so one test's reconciliation
    # cannot be read back by the next.
    function Initialize-ConfigTestState {
        param(
            [string]$ExistingConfigContent,
            [switch]$NoFile
        )

        # Under $TestDrive rather than %TEMP%: Pester removes it after the run, so repeated local
        # runs do not leave a trail of config folders behind. Still one folder per call, because
        # $TestDrive is per-file and these tests must not read each other's config.
        $Folder = Join-Path $TestDrive ("osqConfig_{0}" -f ([guid]::NewGuid().ToString("N")))
        New-Item -Path $Folder -ItemType Directory -Force | Out-Null
        $ConfigFile = Join-Path $Folder -ChildPath "config.json"

        if (-not $NoFile) {
            Set-Content -Path $ConfigFile -Value $ExistingConfigContent -Encoding UTF8
        }

        $Script:RunTimeConfig = [PSCustomObject]@{
            ApplicationName = "Test"
            ConfigFile      = [PSCustomObject]@{ Path = $ConfigFile }
        }
        $Script:AppGlobalConfig = $null
        $Script:AppConfig = $null
        $Script:TabConfigProperties = $null
        $Script:GlobalConfigProperties = $null
        $Script:StubActiveTab = $null
        $Script:LogMessages.Clear()

        return $ConfigFile
    }

    function Get-WrittenConfig {
        param([string]$Path)
        Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}

Describe 'Set-ConfigProperty - global config reconciliation' {

    Context 'No config file exists yet' {
        It 'should create every property the schema declares' {
            $ConfigFile = Initialize-ConfigTestState -NoFile

            "C:\temp" | Set-ConfigProperty -Property "LastOutputFolder"

            $Written = Get-WrittenConfig -Path $ConfigFile
            foreach ($SchemaProperty in $Script:GlobalSchema) {
                $Written.PSObject.Properties.Name | Should -Contain $SchemaProperty.Name
            }
        }

        It 'should seed each type with the documented default' {
            $ConfigFile = Initialize-ConfigTestState -NoFile

            "C:\temp" | Set-ConfigProperty -Property "LastOutputFolder"

            $Written = Get-WrittenConfig -Path $ConfigFile
            # Bool with no declared default -> $false; Int -> -1; String -> $null.
            $Written.LogFormOpen | Should -Be $false
            $Written.LastExtensionIndex | Should -Be -1
            $Written.InstanceGuid | Should -BeNullOrEmpty
        }

        It 'should prefer a declared default over the type default' {
            $ConfigFile = Initialize-ConfigTestState -NoFile

            "C:\temp" | Set-ConfigProperty -Property "LastOutputFolder"

            $Written = Get-WrittenConfig -Path $ConfigFile
            $Written.LogLevel | Should -Be "WARNING"
            $Written.TabCapacity | Should -Be 8
            $Written.EnableSyntaxValidation | Should -Be $true
            $Written.ValidationDebounceMilliseconds | Should -Be 400
        }
    }

    Context 'The config file is corrupt' {
        It 'should not throw' {
            $ConfigFile = Initialize-ConfigTestState -ExistingConfigContent "{ this is not json"
            { "C:\temp" | Set-ConfigProperty -Property "LastOutputFolder" } | Should -Not -Throw
        }

        It 'should replace it with a full schema-shaped config rather than leaving it broken' {
            $ConfigFile = Initialize-ConfigTestState -ExistingConfigContent "{ this is not json"

            "C:\temp" | Set-ConfigProperty -Property "LastOutputFolder"

            $Written = Get-WrittenConfig -Path $ConfigFile
            $Written.LastOutputFolder | Should -Be "C:\temp"
            $Written.LogLevel | Should -Be "WARNING"
            foreach ($SchemaProperty in $Script:GlobalSchema) {
                $Written.PSObject.Properties.Name | Should -Contain $SchemaProperty.Name
            }
        }

        It 'should say so in the log rather than failing silently' {
            $null = Initialize-ConfigTestState -ExistingConfigContent "{ this is not json"

            "C:\temp" | Set-ConfigProperty -Property "LastOutputFolder"

            ($Script:LogMessages -join "`n") | Should -Match "Config file corrupt"
        }

        It 'should treat a truncated but well-formed-looking file as corrupt too' {
            $ConfigFile = Initialize-ConfigTestState -ExistingConfigContent '{ "LogLevel": "DEBUG", "TabCapacity":'

            { "C:\temp" | Set-ConfigProperty -Property "LastOutputFolder" } | Should -Not -Throw
            (Get-WrittenConfig -Path $ConfigFile).LastOutputFolder | Should -Be "C:\temp"
        }
    }

    Context 'The config file is partial - written by an older version' {
        It 'should add a property the schema gained since, with its schema default' {
            # TabCapacity and the validation settings postdate the earliest config files.
            $ConfigFile = Initialize-ConfigTestState -ExistingConfigContent '{ "LastOutputFolder": "C:\\old", "LogLevel": "DEBUG" }'

            "C:\new" | Set-ConfigProperty -Property "LastOutputFolder"

            $Written = Get-WrittenConfig -Path $ConfigFile
            $Written.TabCapacity | Should -Be 8
            $Written.EnableSyntaxValidation | Should -Be $true
            $Written.SessionKeepAliveMinutes | Should -Be 5
        }

        It 'should leave a value the user already chose alone' {
            $ConfigFile = Initialize-ConfigTestState -ExistingConfigContent '{ "LastOutputFolder": "C:\\old", "LogLevel": "DEBUG", "TabCapacity": 3 }'

            "C:\new" | Set-ConfigProperty -Property "LastOutputFolder"

            $Written = Get-WrittenConfig -Path $ConfigFile
            $Written.LogLevel | Should -Be "DEBUG"
            $Written.TabCapacity | Should -Be 3
        }

        It 'should write the property that was actually being set' {
            $ConfigFile = Initialize-ConfigTestState -ExistingConfigContent '{ "LastOutputFolder": "C:\\old" }'

            "C:\new" | Set-ConfigProperty -Property "LastOutputFolder"

            (Get-WrittenConfig -Path $ConfigFile).LastOutputFolder | Should -Be "C:\new"
        }
    }

    Context 'The config file carries a property the schema no longer declares' {
        It 'should drop it on the next write' {
            $ConfigFile = Initialize-ConfigTestState -ExistingConfigContent '{ "LastOutputFolder": "C:\\old", "RetiredSetting": "keep-me-not" }'

            # The removal happens on the in-memory reconciliation pass, which runs when
            # $Script:AppGlobalConfig is already populated - i.e. from the second call onwards.
            "C:\new" | Set-ConfigProperty -Property "LastOutputFolder"
            "C:\newer" | Set-ConfigProperty -Property "LastOutputFolder"

            $Written = Get-WrittenConfig -Path $ConfigFile
            $Written.PSObject.Properties.Name | Should -Not -Contain "RetiredSetting"
            $Written.LastOutputFolder | Should -Be "C:\newer"
        }
    }

    Context 'Value coercion follows the declared type' {
        It 'should store an Int as a number even when a string is supplied' {
            $ConfigFile = Initialize-ConfigTestState -NoFile

            "4" | Set-ConfigProperty -Property "TabCapacity"

            $Written = Get-WrittenConfig -Path $ConfigFile
            $Written.TabCapacity | Should -Be 4
            # A number, not the string "4" - ConvertFrom-Json widens it to [long], which is fine;
            # what matters is that a caller can compare and arithmetic on it without a cast.
            $Written.TabCapacity | Should -Not -BeOfType [string]
            ($Written.TabCapacity + 1) | Should -Be 5
        }

        It 'should store a Bool as a boolean even when a string is supplied' {
            $ConfigFile = Initialize-ConfigTestState -NoFile

            "yes" | Set-ConfigProperty -Property "LogFormWordWrap"

            (Get-WrittenConfig -Path $ConfigFile).LogFormWordWrap | Should -Be $true
        }

        It 'should store a String as given' {
            $ConfigFile = Initialize-ConfigTestState -NoFile

            "Grüße - 日本語" | Set-ConfigProperty -Property "LastOutputFolder"

            (Get-WrittenConfig -Path $ConfigFile).LastOutputFolder | Should -Be "Grüße - 日本語"
        }
    }

    Context 'An unknown property' {
        It 'should warn instead of inventing a setting' {
            $ConfigFile = Initialize-ConfigTestState -NoFile

            "value" | Set-ConfigProperty -Property "ThisPropertyDoesNotExist"

            ($Script:LogMessages -join "`n") | Should -Match "was not found in either the tab or global config schema"
            (Get-WrittenConfig -Path $ConfigFile).PSObject.Properties.Name | Should -Not -Contain "ThisPropertyDoesNotExist"
        }

        It 'should still leave a valid config file behind' {
            $ConfigFile = Initialize-ConfigTestState -NoFile

            "value" | Set-ConfigProperty -Property "ThisPropertyDoesNotExist"

            { Get-WrittenConfig -Path $ConfigFile } | Should -Not -Throw
            (Get-WrittenConfig -Path $ConfigFile).LogLevel | Should -Be "WARNING"
        }
    }

    Context '-Reset' {
        It 'should delete the existing config file and rebuild from the schema' {
            $ConfigFile = Initialize-ConfigTestState -ExistingConfigContent '{ "LastOutputFolder": "C:\\old", "LogLevel": "DEBUG", "TabCapacity": 3 }'

            Set-ConfigProperty -Reset

            $Written = Get-WrittenConfig -Path $ConfigFile
            $Written.LastOutputFolder | Should -BeNullOrEmpty
            $Written.LogLevel | Should -Be "WARNING"
            $Written.TabCapacity | Should -Be 8
        }
    }
}

Describe 'Set-ConfigProperty - tab config reconciliation' {

    Context 'A tab-scope property' {
        It 'should build a full tab config object from the schema' {
            $ConfigFile = Initialize-ConfigTestState -NoFile

            "jdoe" | Set-ConfigProperty -Property "UserName"

            foreach ($SchemaProperty in $Script:TabSchema) {
                $Script:AppConfig.PSObject.Properties.Name | Should -Contain $SchemaProperty.Name
            }
            $Script:AppConfig.UserName | Should -Be "jdoe"
        }

        It 'should not touch the global config file, since tabs are flushed by Save-TabSessions' {
            $ConfigFile = Initialize-ConfigTestState -NoFile

            "jdoe" | Set-ConfigProperty -Property "UserName"

            Test-Path -Path $ConfigFile | Should -Be $false
        }

        It 'should encrypt a SecureString property rather than storing the plaintext' {
            $null = Initialize-ConfigTestState -NoFile

            "Sup3rSecretValue-DoNotLeak" | Set-ConfigProperty -Property "Password"

            $Script:AppConfig.Password | Should -Not -Be "Sup3rSecretValue-DoNotLeak"
            $Script:AppConfig.Password | Should -Match '^[0-9a-fA-F]+$'
            ($Script:AppConfig.Password | ConvertTo-SecureString | ForEach-Object {
                [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($_))
            }) | Should -BeExactly "Sup3rSecretValue-DoNotLeak"
        }

        It 'should clear a SecureString property when given an empty value' {
            $null = Initialize-ConfigTestState -NoFile

            "" | Set-ConfigProperty -Property "Password"

            $Script:AppConfig.Password | Should -BeNullOrEmpty
        }

        It 'should refuse -Reset, which only means anything for the global file' {
            $null = Initialize-ConfigTestState -NoFile

            "jdoe" | Set-ConfigProperty -Property "UserName" -Reset

            ($Script:LogMessages -join "`n") | Should -Match "-Reset only applies to the global config file"
        }

        It 'should push the rebuilt object back onto the active tab, not just the module variable' {
            # $Config is rebuilt through a JSON round-trip, so it is a new reference. Without this
            # push, the next tab switch would read the tab's stale AppConfig and revert the change.
            $null = Initialize-ConfigTestState -NoFile
            $Script:StubActiveTab = [PSCustomObject]@{ Id = "a"; AppConfig = [PSCustomObject]@{ UserName = "stale" } }

            "jdoe" | Set-ConfigProperty -Property "UserName"

            $Script:StubActiveTab.AppConfig.UserName | Should -Be "jdoe"
            [object]::ReferenceEquals($Script:StubActiveTab.AppConfig, $Script:AppConfig) | Should -Be $true
        }
    }

    Context 'A PSObject property built from a "DisplayName - DoId" string' {
        It 'should split the display name from the identifier' {
            $null = Initialize-ConfigTestState -NoFile

            "Production - 7" | Set-ConfigProperty -Property "CurrentDataConnection"

            $Script:AppConfig.CurrentDataConnection.DoId | Should -Be 7
            $Script:AppConfig.CurrentDataConnection.DisplayName | Should -Be "Production"
            $Script:AppConfig.CurrentDataConnection.FullName | Should -Be "Production - 7"
        }

        It 'should split on the last separator when the display name contains one too' {
            $null = Initialize-ConfigTestState -NoFile

            "North - South - 42" | Set-ConfigProperty -Property "CurrentDataConnection"

            $Script:AppConfig.CurrentDataConnection.DoId | Should -Be 42
            $Script:AppConfig.CurrentDataConnection.DisplayName | Should -Be "North - South"
        }

        It 'should treat a value with no separator as the identifier alone' {
            $null = Initialize-ConfigTestState -NoFile

            "12345" | Set-ConfigProperty -Property "CurrentDataConnection"

            $Script:AppConfig.CurrentDataConnection.DoId | Should -Be "12345"
            $Script:AppConfig.CurrentDataConnection.DisplayName | Should -BeNullOrEmpty
        }

        It 'should accept the identifier and display name as two pipeline items' {
            $null = Initialize-ConfigTestState -NoFile

            @(7, "Production") | Set-ConfigProperty -Property "CurrentDataConnection"

            $Script:AppConfig.CurrentDataConnection.DoId | Should -Be 7
            $Script:AppConfig.CurrentDataConnection.DisplayName | Should -Be "Production"
            $Script:AppConfig.CurrentDataConnection.FullName | Should -Be "Production - 7"
        }
    }
}
