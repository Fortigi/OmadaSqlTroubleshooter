#Requires -Version 7.0
# Wiring for the client-side validation worker (issue #185) in places that cannot run outside WPF and
# WebView2: the editor's message handler, the execute path, tab close and window close. Asserted on
# the source, as ExecuteQueryStatementWiring.Tests.ps1 does for the execute path.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Script:PrivatePath = [System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private")
    $Script:EventsPath = [System.IO.Path]::Combine($ParentPath, "src", "Lib", "Events")
}

Describe 'The WebMessageReceived handler' -Tag 'Unit' {

    It 'Should only find the tab and hand the message to Invoke-WebViewMessage' {
        $Source = Get-Content -Path (Join-Path $Script:PrivatePath "Initialize-WebViewForTab.ps1") -Raw
        $Handler = ([regex]::Match($Source, '(?s)add_WebMessageReceived\(\{.*?\n                        \}\)')).Value

        $Handler | Should -Not -BeNullOrEmpty
        $Handler | Should -Match 'Invoke-WebViewMessage -TabSession \$HandlerTab'
        $Handler | Should -Not -Match 'Write-LogOutput -LogType DEBUG' -Because "logging happens in Invoke-WebViewMessage, after contentChanged has returned"
        $Handler | Should -Not -Match 'Show-EventInfo'
    }
}

Describe 'Results that would land on newer text are stopped first' -Tag 'Unit' {
    # Issue #185 acceptance criterion 2.

    It 'Should stop the worker before the execute path pushes its own markers' {
        $Source = Get-Content -Path (Join-Path $Script:PrivatePath "Invoke-ExecuteQuery.ps1") -Raw
        $Stop = $Source.IndexOf("Stop-SqlDiagnosticBackground -TabSession (Get-ActiveTabSession)")
        $Diagnose = $Source.IndexOf('$Private:ValidationResult = Get-SqlDiagnostic')

        $Stop | Should -BeGreaterThan 0
        $Diagnose | Should -BeGreaterThan $Stop
    }

    It 'Should stop a closing tab''s worker alongside its background requests' {
        $Source = Get-Content -Path (Join-Path $Script:PrivatePath "Complete-TabClose.ps1") -Raw
        $Source | Should -Match 'Remove-PendingBackgroundRequest -TabSession \$TabToClose\s+(#[^\n]*\s+)*Stop-SqlDiagnosticBackground -TabSession \$TabToClose'
    }

    It 'Should close the validation pool when the window closes' {
        # Worker threads left open keep the process alive after the window has gone (issue #40).
        $Source = Get-Content -Path (Join-Path $Script:EventsPath "MainForm.Definition.ps1") -Raw
        $Closing = ([regex]::Match($Source, '(?s)Add_Closing\(\{.*?\n    \}\)')).Value

        $Closing | Should -Match 'Close-OmadaRequestPool\s+Close-SqlDiagnosticPool'
    }
}
