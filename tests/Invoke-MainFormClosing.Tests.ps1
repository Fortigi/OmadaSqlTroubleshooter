#Requires -Version 7.0

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private", "Invoke-MainFormClosing.ps1"))

    $script:Calls = [System.Collections.Generic.List[string]]::new()
    function Confirm-UnsavedQueryOnClose { $script:Calls.Add("confirm"); return $script:Confirm }
    function Sync-AdHocQueryDraft { param($TabSession) $script:Calls.Add("sync:" + $TabSession.Id) }
    function Save-TabSessions { $script:Calls.Add("tabs") }
    function Save-FormMeasurements { $script:Calls.Add("measurements") }
    function Test-LogFormIsVisible { $false }
    function Test-SqlHistoryFormOpen { $false }
    function Test-SqlSchemaFormIsVisible { $false }
    function Close-OmadaRequestPool { $script:Calls.Add("pool") }
    function Close-SqlDiagnosticPool { $script:Calls.Add("validation-pool") }
}

Describe 'Invoke-MainFormClosing' -Tag 'Unit' {
    BeforeEach {
        $script:Calls.Clear()
        $Script:MainForm = [PSCustomObject]@{ State = "Open" }
        $Script:Tabs = @([PSCustomObject]@{ Id = "a" }, [PSCustomObject]@{ Id = "b" })
        $script:ClosingArgs = [PSCustomObject]@{ Cancel = $false }
    }

    It 'Should keep the window open, and touch nothing, when the user cancels' {
        $script:Confirm = $false

        Invoke-MainFormClosing -ClosingEventArgs $script:ClosingArgs

        $script:ClosingArgs.Cancel | Should -BeTrue
        $Script:MainForm.State | Should -Be "Open"
        @($script:Calls) | Should -Be @("confirm")
    }

    It 'Should ask first, then keep the drafts, save the session and close the pools last' {
        $script:Confirm = $true

        Invoke-MainFormClosing -ClosingEventArgs $script:ClosingArgs

        $script:ClosingArgs.Cancel | Should -BeFalse
        $Script:MainForm.State | Should -Be "Closing"
        @($script:Calls) | Should -Be @("confirm", "sync:a", "sync:b", "tabs", "measurements", "pool", "validation-pool")
    }
}
