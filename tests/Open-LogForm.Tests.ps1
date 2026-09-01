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
        $Script:BodyRedactionStateSource = Get-Content (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Set-BodyRedactionState.ps1") -Raw
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

    Context 'State writer' {

        It 'sets the module scope flag the redactor reads' {
            $Script:BodyRedactionStateSource | Should -Match '\$Script:SkipBodyRedaction = \$Enabled'
        }

        It 'warns once per session that query text now reaches the log' {
            $Script:BodyRedactionStateSource | Should -Match 'SkipBodyRedactionWarned'
            $Script:BodyRedactionStateSource | Should -Match '-LogType WARNING'
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
}
