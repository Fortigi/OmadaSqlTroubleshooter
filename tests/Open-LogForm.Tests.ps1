BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Script:LogFormXamlPath = Join-Path $ParentPath -ChildPath "src\lib\ui\LogForm.xaml"
    $Script:OpenLogFormSource = Get-Content (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Open-LogForm.ps1") -Raw
    $Script:LogLevelEventSource = Get-Content (Join-Path $ParentPath -ChildPath "src\lib\Events\LogForm.Elements.ComboBoxSelectLogLevel.ps1") -Raw

    # Parsed as plain XML, never loaded as WPF: a headless agent cannot resolve System.Windows types.
    $Script:LogFormXaml = [xml](Get-Content $Script:LogFormXamlPath -Raw)
    $Script:XamlNamespace = New-Object System.Xml.XmlNamespaceManager($Script:LogFormXaml.NameTable)
    $Script:XamlNamespace.AddNamespace("w", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
    $Script:XamlNamespace.AddNamespace("x", "http://schemas.microsoft.com/winfx/2006/xaml")
    $Script:LogLevelComboBox = $Script:LogFormXaml.SelectSingleNode("//w:ComboBox[@x:Name='ComboBoxSelectLogLevel']", $Script:XamlNamespace)
}

Describe 'LogForm.xaml log level combo box' {

    It 'is present in the log form' {
        $Script:LogLevelComboBox | Should -Not -BeNullOrEmpty
    }

    It 'does not preselect an item, so its SelectionChanged handler cannot store a level before the stored one is applied' {
        # SelectedIndex="0" selected LOG while Import-EventObjects had already wired
        # SelectionChanged, so LOG was written to the config before Open-LogForm restored the
        # intended level (issue #63).
        $Script:LogLevelComboBox.Attributes["SelectedIndex"] | Should -BeNullOrEmpty
        $Script:LogLevelComboBox.Attributes["SelectedItem"] | Should -BeNullOrEmpty
        $Script:LogLevelComboBox.Attributes["SelectedValue"] | Should -BeNullOrEmpty
    }

    It 'still offers every level the application can filter on' {
        $Items = $Script:LogLevelComboBox.ChildNodes | Where-Object { $_.LocalName -eq "ComboBoxItem" }
        $Contents = $Items | ForEach-Object { $_.GetAttribute("Content") }

        foreach ($Level in @("LOG", "INFO", "WARNING", "ERROR", "FATAL", "DEBUG", "VERBOSE", "VERBOSE2")) {
            $Contents | Should -Contain $Level
        }
    }
}

Describe 'ComboBoxSelectLogLevel SelectionChanged handler' {

    It 'ignores a selection change that carries no selected item' {
        # Without the guard an empty selection stores $null as the log level.
        $Script:LogLevelEventSource | Should -Match 'SelectedItem'
        $Script:LogLevelEventSource | Should -Match '(?s)if\s*\(\s*\$null\s*-eq.*SelectedItem'
    }
}

Describe 'Open-LogForm log level fallback' {

    It 'does not hardcode a log level default any more' {
        $Script:OpenLogFormSource | Should -Not -Match '"INFO"'
    }

    It 'reads the default from the config schema instead' {
        $Script:OpenLogFormSource | Should -Match 'Get-ConfigSchemaDefault -Property "LogLevel"'
    }
}

Describe 'Show request body option (issue #62)' {

    BeforeAll {
        $ParentPath = Split-Path -Path $PSScriptRoot -Parent
        $Script:ShowRequestBodyCheckBox = $Script:LogFormXaml.SelectSingleNode("//w:CheckBox[@x:Name='CheckboxShowRequestBody']", $Script:XamlNamespace)
        $Script:ShowRequestBodyEventSource = Get-Content (Join-Path $ParentPath -ChildPath "src\lib\Events\LogForm.Elements.CheckboxShowRequestBody.ps1") -Raw
        $Script:EntryPointSource = Get-Content (Join-Path $ParentPath -ChildPath "src\lib\functions\Public\Invoke-OmadaSqlTroubleshooter.ps1") -Raw
        $Script:GlobalConfigSchema = Get-Content (Join-Path $ParentPath -ChildPath "src\lib\schema\appGlobalConfigSchema.json") -Raw | ConvertFrom-Json
    }

    Context 'Checkbox' {

        It 'sits in the log form bottom bar' {
            $Script:ShowRequestBodyCheckBox | Should -Not -BeNullOrEmpty
            $Script:ShowRequestBodyCheckBox.GetAttribute("Content") | Should -Be "Show request body"
        }

        It 'starts unchecked, so the safe default survives a fresh install' {
            $Script:ShowRequestBodyCheckBox.Attributes["IsChecked"] | Should -BeNullOrEmpty
        }

        It 'warns in its tooltip that the query text reaches an exported log file' {
            $ToolTip = $Script:ShowRequestBodyCheckBox.GetAttribute("ToolTip")

            $ToolTip | Should -Match "exported log file"
            # The tooltip is where the checkbox label and the cmdlet switch are tied together.
            $ToolTip | Should -Match "SkipBodyRedaction"
        }
    }

    Context 'Event handler' {

        It 'routes both directions through the single state writer' {
            $Script:ShowRequestBodyEventSource | Should -Match 'Add_Checked'
            $Script:ShowRequestBodyEventSource | Should -Match 'Add_UnChecked'
            $Script:ShowRequestBodyEventSource | Should -Match 'Set-BodyRedactionState -Enabled \$true'
            $Script:ShowRequestBodyEventSource | Should -Match 'Set-BodyRedactionState -Enabled \$false'
        }

        It 'persists the choice like the other log viewer checkboxes do' {
            $Script:ShowRequestBodyEventSource | Should -Match 'Set-ConfigProperty -Property "SkipBodyRedaction"'
        }
    }

    Context 'Command line' {

        It 'offers a -SkipBodyRedaction switch named after the OmadaWeb.PS one it drives' {
            $Script:EntryPointSource | Should -Match '\[switch\]\$SkipBodyRedaction'
        }

        It 'seeds the runtime state before the first request' {
            $Script:EntryPointSource | Should -Match 'SkipBodyRedaction\s+= \$SkipBodyRedaction.IsPresent'
            $Script:EntryPointSource | Should -Match '\$Script:SkipBodyRedaction = \$SkipBodyRedaction.IsPresent'
        }

        It 'documents the switch' {
            $Script:EntryPointSource | Should -Match '\.PARAMETER SkipBodyRedaction'
        }

        It 'rearms the once-per-session warning, since the module outlives an application session' {
            # Without this, a second Invoke-OmadaSqlTroubleshooter in the same console would enable
            # body logging without warning about it.
            $Script:EntryPointSource | Should -Match '\$Script:SkipBodyRedactionWarned = \$false'
        }
    }

    Context 'Persistence' {

        It 'is a known global config property, so Set-ConfigProperty stores it instead of warning' {
            ($Script:GlobalConfigSchema | Where-Object { $_.Name -eq "SkipBodyRedaction" }).Type | Should -Be "Bool"
        }

        It 'reflects the resolved state in the checkbox when the log viewer opens' {
            $Script:OpenLogFormSource | Should -Match 'CheckboxShowRequestBody.IsChecked'
            $Script:OpenLogFormSource | Should -Match '\$Script:RunTimeConfig.Logging.SkipBodyRedaction'
        }
    }

    Context 'The file it now also reaches (issue #121)' {

        BeforeAll {
            $ParentPath = Split-Path -Path $PSScriptRoot -Parent
            $Script:BodyRedactionStateSource = Get-Content (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Set-BodyRedactionState.ps1") -Raw
        }

        It 'warns that the query text now goes to the session log file as well' {
            # Enabling the option puts query text somewhere permanent. A user attaching a log to a
            # support ticket should not have to discover that afterwards, and "the log window and
            # anything exported from it" stopped being the whole truth when the file was added.
            $Script:BodyRedactionStateSource | Should -Match "session log file"
        }
    }
}

Describe 'Session log file, from the log window (issue #121)' {

    BeforeAll {
        $ParentPath = Split-Path -Path $PSScriptRoot -Parent
        $Script:OpenLogFolderButton = $Script:LogFormXaml.SelectSingleNode("//w:Button[@x:Name='ButtonOpenLogFolder']", $Script:XamlNamespace)
        $Script:SessionLogPathTextBlock = $Script:LogFormXaml.SelectSingleNode("//w:TextBlock[@x:Name='TextBlockSessionLogPath']", $Script:XamlNamespace)
        $Script:OpenLogFolderEventSource = Get-Content (Join-Path $ParentPath -ChildPath "src\lib\Events\LogForm.Elements.ButtonOpenLogFolder.ps1") -Raw
        $Script:EntryPointSource = Get-Content (Join-Path $ParentPath -ChildPath "src\lib\functions\Public\Invoke-OmadaSqlTroubleshooter.ps1") -Raw
        # The row moved into its own function when the checkbox made it reachable twice (issue #138).
        $Script:UpdateSessionLogPathSource = Get-Content (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Update-LogFormSessionLogPath.ps1") -Raw
    }

    Context 'The window says where the file is' {

        It 'shows the path' {
            # "A predictable location, discoverable from the log window" - the issue offers an "open
            # log folder" action OR the path in the window. This is both, because a path you can
            # read is also a path you can paste into a support ticket.
            $Script:SessionLogPathTextBlock | Should -Not -BeNullOrEmpty
        }

        It 'fills the path in when the window opens' {
            $Script:OpenLogFormSource | Should -Match 'Update-LogFormSessionLogPath'
            $Script:UpdateSessionLogPathSource | Should -Match 'TextBlockSessionLogPath'
            $Script:UpdateSessionLogPathSource | Should -Match '\$Script:SessionLogFile'
        }

        It 'checks both new elements are there before touching either' {
            # Assigning to a property of $null throws, Open-LogForm's catch logs an ERROR, and
            # logging an ERROR under $ErrorActionPreference = Stop throws again - so a XAML mismatch
            # or a partial harness would turn "the log window opens" into an error cascade. Guarding
            # only the TextBlock and then dereferencing the Button was exactly that hole.
            $Script:UpdateSessionLogPathSource | Should -Match '\$null -eq \$Script:LogForm\.Elements\.TextBlockSessionLogPath -or \$null -eq \$Script:LogForm\.Elements\.ButtonOpenLogFolder'
        }

        It 'offers a button that opens the folder' {
            $Script:OpenLogFolderButton | Should -Not -BeNullOrEmpty
            # The window's Button style disables buttons by default; every usable one opts back in.
            $Script:OpenLogFolderButton.GetAttribute("IsEnabled") | Should -BeExactly "True"
        }

        It 'opens the folder the file is actually in, not a path of its own' {
            $Script:OpenLogFolderEventSource | Should -Match '\$Script:SessionLogFile'
            $Script:OpenLogFolderEventSource | Should -Match 'Add_Click'
        }

        It 'reports a failure without unwinding the click handler' {
            # Write-LogOutput -LogType ERROR ends in Write-Error, and the application runs with
            # $ErrorActionPreference = Stop - so logging an ERROR from a WPF click handler throws
            # into the dispatcher's unhandled path and stacks dialogs. Write-ContainedErrorLog is
            # this repository's answer, and the same rule CleanupPathsDoNotThrow.Tests.ps1 applies
            # to the other handlers that must carry on afterwards.
            $Script:OpenLogFolderEventSource | Should -Match 'Write-ContainedErrorLog'
            $Script:OpenLogFolderEventSource | Should -Not -Match 'Write-LogOutput -LogType ERROR'
        }
    }

    Context 'The application starts and stops the file' {

        It 'starts it once the configuration that configures it has been read' {
            $Script:EntryPointSource | Should -Match 'Initialize-GlobalConfigSettings -Reset:\$Reset'
            $Script:EntryPointSource | Should -Match 'Start-SessionLogFile'
        }

        It 'holds the start-up lines before that, so a start-up failure reaches the file too' {
            $Script:EntryPointSource | Should -Match '\$Script:SessionLogFile = New-SessionLogFileState'
        }

        It 'resolves nothing to create that buffer, because resolution can log' {
            # Get-ConfigSchemaDefault logs a WARNING for a property it cannot find - and a line
            # logged BEFORE the buffer exists has nowhere to go, which is the one thing the buffer
            # is for. The level here is provisional anyway: held lines are re-filtered against the
            # configured level once Start-SessionLogFile has resolved it.
            $Script:EntryPointSource | Should -Match '\$Script:SessionLogFile = New-SessionLogFileState\s*\r?\n'
        }

        It 'closes it on the way out' {
            $Script:EntryPointSource | Should -Match 'Stop-SessionLogFile'
        }
    }

    Context 'Clearing the window does not touch the file' {

        It 'clears only AppLogObject, as it always did' {
            # The file keeps the session; the window keeps the view. Open-LogForm must not have
            # acquired any knowledge of the file's writer along the way.
            $Script:OpenLogFormSource | Should -Match 'AppLogObject.Clear\(\)'
            $Script:OpenLogFormSource | Should -Not -Match 'Stop-SessionLogFile'
        }
    }
}

Describe 'Write log file checkbox (issue #138)' {

    BeforeAll {
        $ParentPath = Split-Path -Path $PSScriptRoot -Parent
        $Script:SessionLogFileCheckBox = $Script:LogFormXaml.SelectSingleNode("//w:CheckBox[@x:Name='CheckboxSessionLogFile']", $Script:XamlNamespace)
        $Script:SessionLogFileEventSource = Get-Content (Join-Path $ParentPath -ChildPath "src\lib\Events\LogForm.Elements.CheckboxSessionLogFile.ps1") -Raw
        $Script:SetSessionLogFileEnabledSource = Get-Content (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Set-SessionLogFileEnabled.ps1") -Raw
        $Script:GlobalConfigSchema = Get-Content (Join-Path $ParentPath -ChildPath "src\lib\schema\appGlobalConfigSchema.json") -Raw | ConvertFrom-Json
    }

    Context 'Checkbox' {

        It 'sits in the row that shows the file, next to the Folder button' {
            $Script:SessionLogFileCheckBox | Should -Not -BeNullOrEmpty
            $Script:SessionLogFileCheckBox.GetAttribute("Content") | Should -Be "Write log file"
            $Script:SessionLogFileCheckBox.ParentNode.SelectSingleNode("w:Button[@x:Name='ButtonOpenLogFolder']", $Script:XamlNamespace) | Should -Not -BeNullOrEmpty
            $Script:SessionLogFileCheckBox.ParentNode.SelectSingleNode("w:TextBlock[@x:Name='TextBlockSessionLogPath']", $Script:XamlNamespace) | Should -Not -BeNullOrEmpty
        }

        It 'starts unchecked, so off-by-default survives a fresh install' {
            # Open-LogForm sets the state from the resolved setting; a checked default in the XAML
            # would be a second answer to the same question.
            $Script:SessionLogFileCheckBox.Attributes["IsChecked"] | Should -BeNullOrEmpty
        }

        It 'states in its tooltip that a file started now has only what follows' {
            $ToolTip = $Script:SessionLogFileCheckBox.GetAttribute("ToolTip")

            $ToolTip | Should -Match "from this moment on"
            $ToolTip | Should -Match "Export Log File"
        }
    }

    Context 'Event handler' {

        It 'routes both directions through the single state writer' {
            $Script:SessionLogFileEventSource | Should -Match 'Add_Checked'
            $Script:SessionLogFileEventSource | Should -Match 'Add_UnChecked'
            $Script:SessionLogFileEventSource | Should -Match 'Set-SessionLogFileEnabled -Enabled \$true'
            $Script:SessionLogFileEventSource | Should -Match 'Set-SessionLogFileEnabled -Enabled \$false'
        }

        It 'puts the path label and the Folder button back in step afterwards' {
            ($Script:SessionLogFileEventSource | Select-String -Pattern 'Update-LogFormSessionLogPath' -AllMatches).Matches.Count | Should -Be 2
        }
    }

    Context 'State writer' {

        It 'persists the choice like the other log viewer checkboxes do' {
            $Script:SetSessionLogFileEnabledSource | Should -Match 'Set-ConfigProperty -Property "EnableSessionLogFile"'
        }

        It 'persists before it starts, because the start reads the persisted value' {
            # Start-SessionLogFile asks Get-LogFileSetting whether a file is wanted, and that reads
            # $Script:AppGlobalConfig - which is what Set-ConfigProperty updates. The other order
            # reads the old value and writes nothing.
            # The call forms, not the names: both are discussed in the comments above the code, so
            # the first textual mention of either is prose rather than the statement being ordered.
            $PersistIndex = $Script:SetSessionLogFileEnabledSource.IndexOf('$Enabled | Set-ConfigProperty -Property "EnableSessionLogFile"')
            $StartIndex = $Script:SetSessionLogFileEnabledSource.IndexOf('Start-SessionLogFile | Out-Null')

            $PersistIndex | Should -BeGreaterThan -1
            $StartIndex | Should -BeGreaterThan $PersistIndex
        }

        It 'stops the file through the function that closes it under the write lock' {
            $Script:SetSessionLogFileEnabledSource | Should -Match 'Stop-SessionLogFile'
        }

        It 'reports a failure without unwinding the click handler' {
            $Script:SetSessionLogFileEnabledSource | Should -Match 'Write-ContainedErrorLog'
            $Script:SetSessionLogFileEnabledSource | Should -Not -Match 'Write-LogOutput -LogType ERROR'
        }

        It 'is a known global config property, so Set-ConfigProperty stores it instead of warning' {
            ($Script:GlobalConfigSchema | Where-Object { $_.Name -eq "EnableSessionLogFile" }).Type | Should -Be "Bool"
        }
    }

    Context 'Opening the window' {

        It 'reflects the resolved setting in the checkbox' {
            $Script:OpenLogFormSource | Should -Match 'CheckboxSessionLogFile.IsChecked = \(Get-LogFileSetting\).Enabled'
        }

        It 'does so before the handlers are wired, so opening the window starts nothing' {
            # Setting IsChecked raises Checked/UnChecked. With the handler already wired, merely
            # opening the window would rewrite the setting, and a session whose file could not be
            # opened would retry the open and warn again on every open.
            # The call form: the comment above the assignment names Import-EventObjects too, and the
            # point being asserted is where the statement is.
            $CheckboxIndex = $Script:OpenLogFormSource.IndexOf('Elements.CheckboxSessionLogFile.IsChecked = (Get-LogFileSetting).Enabled')
            $ImportIndex = $Script:OpenLogFormSource.IndexOf('Import-EventObjects -ClassName')

            $CheckboxIndex | Should -BeGreaterThan -1
            $ImportIndex | Should -BeGreaterThan $CheckboxIndex
        }
    }
}
