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
