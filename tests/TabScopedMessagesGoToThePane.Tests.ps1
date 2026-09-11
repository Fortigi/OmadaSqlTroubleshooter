# Issue #93 replaced two mechanisms with two others, and the half that is easy to get wrong is the
# half about what NO LONGER happens: no floating popup for any operation, and no modal dialog for a
# query failure. Absence is exactly where a check passes for the wrong reason, so these assertions
# observe the dialog and popup functions themselves rather than the log - the message still goes to
# the log on every path, so a log-based check would be green whatever the UI did.

BeforeAll {
    $Script:SourceRoot = Join-Path $PSScriptRoot -ChildPath "..\src"
    $PrivatePath = Join-Path $Script:SourceRoot -ChildPath "Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Write-TabMessage.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
}

Describe "Show-PopupWindow is gone" {
    It "no longer exists in the source tree" {
        # Acceptance criterion 3's second half - "ideally not used at all". All six callers were
        # converted, so the function itself goes rather than being left as a loaded gun.
        Join-Path $Script:SourceRoot -ChildPath "Lib\Functions\Private\Show-PopupWindow.ps1" |
            Test-Path | Should -BeFalse
    }

    It "is called from nowhere" {
        $Private:Callers = Get-ChildItem -Path $Script:SourceRoot -Recurse -Filter "*.ps1" |
            Select-String -Pattern "Show-PopupWindow" -SimpleMatch

        $Private:Callers | Should -BeNullOrEmpty
    }

    It "left no per-tab popup slot behind on the tab session" {
        # A leftover ExecutePopup field would be a second source of truth about "is this tab busy?",
        # which is what produced the orphaned windows in the first place.
        $Private:NewTab = Get-Content -Path (Join-Path $Script:SourceRoot -ChildPath "Lib\Functions\Private\New-TabSession.ps1") -Raw

        $Private:NewTab | Should -Not -Match "ExecutePopup"
    }
}

Describe "A query failure reaches the pane and not a dialog" {
    BeforeEach {
        $Script:TabA = [pscustomobject]@{
            Id            = "tab-A"
            QueryMessages = [System.Collections.Generic.List[string]]::new()
            Elements      = @{
                TextBoxQueryMessages  = [pscustomobject]@{ Text = "" }
                TabControlQueryOutput = [pscustomobject]@{ SelectedIndex = 0 }
            }
        }
        $Script:DialogCalls = [System.Collections.Generic.List[string]]::new()
    }

    It "routes a tab-scoped message to the pane" {
        # The shape Write-LogOutput now uses for -TabScoped. Asserted through the same entry point the
        # application calls, so a change of mind there shows up here.
        Add-TabMessage -TabSession $Script:TabA -Text "Failure occurred:`r`n`r`nInvalid column name 'Idenity'." -Focus

        $Script:TabA.Elements.TextBoxQueryMessages.Text | Should -Match "Invalid column name"
        $Script:DialogCalls.Count | Should -Be 0
    }

    It "keeps the error text whole, because the user has to be able to copy it" {
        # A long SQL Server error was painful to read in a message box and worse to get out of one.
        # The pane is a read-only TextBox precisely so selection and Ctrl+C work; the text must
        # therefore arrive unabridged.
        $Private:Long = "Msg 207, Level 16, State 1, Line 4`r`nInvalid column name 'Idenity'.`r`n" + ("x" * 4000)

        Add-TabMessage -TabSession $Script:TabA -Text $Private:Long -Focus

        $Script:TabA.Elements.TextBoxQueryMessages.Text.Length | Should -BeGreaterOrEqual $Private:Long.Length
    }
}

Describe "Write-LogOutput draws the line where the issue says it does" {
    BeforeAll {
        $Script:LogSource = Get-Content -Path (Join-Path $Script:SourceRoot -ChildPath "Lib\Functions\Private\Write-LogOutput.ps1") -Raw
    }

    It "sends a tab-scoped message to the pane" {
        $Script:LogSource | Should -Match 'if \(\$TabScoped\)'
        $Script:LogSource | Should -Match 'Add-TabMessage'
    }

    It "still shows a dialog for anything that is not tab-scoped" {
        # Acceptance criterion 9. An application-level failure - configuration, WebView2 startup,
        # module loading - is not about a tab, the user may have no tab open, and a status bar is too
        # quiet for it.
        $Script:LogSource | Should -Match 'Show-LogMessageDialog'
    }

    It "focuses the pane on errors but not on warnings" {
        # "Query did not return any results" is a WARNING on a SUCCESSFUL execute. Focusing for it
        # would break criterion 7, which asks for Results to stay selected on success.
        $Script:LogSource | Should -Match '-Focus:\$LogMessage\.ShowError'
    }

    It "no longer holds tab-scoped messages in a queue" {
        # The pane is per tab and durable, so there is nothing left to hold - which is what made
        # Add-TabScopedMessage's queue redundant rather than merely unused.
        Join-Path $Script:SourceRoot -ChildPath "Lib\Functions\Private\Add-TabScopedMessage.ps1" |
            Test-Path | Should -BeFalse

        $Script:LogSource | Should -Not -Match 'Add-TabScopedMessage -TabSession'
    }
}

Describe "The Messages pane exists beside the results grid" {
    BeforeAll {
        $Script:TabXamlPath = Join-Path $Script:SourceRoot -ChildPath "Lib\ui\MainFormTabContent.xaml"
        [xml]$Script:TabXaml = Get-Content -Path $Script:TabXamlPath -Raw
    }

    It "wraps the results grid in a two-tab control" {
        # Parsed rather than pattern-matched: the thing that matters is the shape of the tree the
        # application will actually load.
        $Private:Manager = New-Object System.Xml.XmlNamespaceManager($Script:TabXaml.NameTable)
        $Private:Manager.AddNamespace("d", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")

        $Private:TabControl = $Script:TabXaml.DocumentElement.SelectSingleNode("//d:TabControl[@*[local-name()='Name']='TabControlQueryOutput']", $Private:Manager)
        $Private:TabControl | Should -Not -BeNullOrEmpty

        $Private:Items = $Private:TabControl.SelectNodes("d:TabItem", $Private:Manager)
        @($Private:Items).Count | Should -Be 2
    }

    It "puts Results first and Messages second, which is the order the code selects by index" {
        # Initialize-FormObject registers elements by type and TabItem is not in its list, so nothing
        # can reach these by name - selection is by index, and the index is only correct if the order
        # here is. A swap would silently focus the wrong pane on every failure.
        $Private:Manager = New-Object System.Xml.XmlNamespaceManager($Script:TabXaml.NameTable)
        $Private:Manager.AddNamespace("d", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")

        $Private:Items = @($Script:TabXaml.DocumentElement.SelectNodes("//d:TabControl[@*[local-name()='Name']='TabControlQueryOutput']/d:TabItem", $Private:Manager))

        $Private:Items[0].Header | Should -Be "Results"
        $Private:Items[1].Header | Should -Be "Messages"
    }

    It "holds the results grid in the Results tab" {
        $Private:Manager = New-Object System.Xml.XmlNamespaceManager($Script:TabXaml.NameTable)
        $Private:Manager.AddNamespace("d", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")

        $Private:Grid = $Script:TabXaml.DocumentElement.SelectSingleNode("//d:TabControl[@*[local-name()='Name']='TabControlQueryOutput']/d:TabItem[1]//d:DataGrid", $Private:Manager)

        $Private:Grid | Should -Not -BeNullOrEmpty
    }

    It "makes the Messages pane read-only and therefore selectable and copyable" {
        # Acceptance criterion 6. A TextBlock would render the text and refuse to let the user take it
        # anywhere, which is the complaint the message box already attracted.
        $Private:Manager = New-Object System.Xml.XmlNamespaceManager($Script:TabXaml.NameTable)
        $Private:Manager.AddNamespace("d", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")

        $Private:Box = $Script:TabXaml.DocumentElement.SelectSingleNode("//d:TextBox[@*[local-name()='Name']='TextBoxQueryMessages']", $Private:Manager)

        $Private:Box | Should -Not -BeNullOrEmpty
        $Private:Box.IsReadOnly | Should -Be "True"
    }

    It "gives the status bar a single message block" {
        # Column 0 subsumed the connection state, so there is one stretchy block and one writer -
        # which is also what makes the open question in issue #71 answerable by grep.
        $Private:Manager = New-Object System.Xml.XmlNamespaceManager($Script:TabXaml.NameTable)
        $Private:Manager.AddNamespace("d", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")

        $Script:TabXaml.DocumentElement.SelectSingleNode("//d:TextBlock[@Name='TextBlockStatusBarMessage']", $Private:Manager) | Should -Not -BeNullOrEmpty
        $Script:TabXaml.DocumentElement.SelectSingleNode("//d:TextBlock[@Name='TextBlockStatusBarConnectionStatus']", $Private:Manager) | Should -BeNullOrEmpty
    }

    It "is written only through Set-TabStatusMessage" {
        # The single-writer property this issue introduced. Any direct assignment to the block outside
        # its own function is the second writer issue #71 went looking for.
        $Private:Direct = Get-ChildItem -Path $Script:SourceRoot -Recurse -Filter "*.ps1" |
            Select-String -Pattern "TextBlockStatusBarMessage" |
            Where-Object { $_.Path -notlike "*Set-TabStatusMessage.ps1" }

        $Private:Direct | Should -BeNullOrEmpty
    }
}
