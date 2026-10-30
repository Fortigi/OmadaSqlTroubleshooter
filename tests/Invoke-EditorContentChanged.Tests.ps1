#Requires -Version 7.0
# Tests for what runs on the WPF dispatcher on every keystroke in the editor (issue #185).

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Script:PrivatePath = [System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private")

    . (Join-Path $Script:PrivatePath "Invoke-EditorContentChanged.ps1")
    . (Join-Path $Script:PrivatePath "Request-SqlSyntaxValidation.ps1")

    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$Message, [string]$LogType = "INFO", $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
        process { }
    }

    $script:HeaderRefreshes = 0
    function Update-TabHeaderTitle {
        param($TabSession)
        $script:HeaderRefreshes++
    }

    $script:Setting = [PSCustomObject]@{ Enabled = $true; SchemaEnabled = $true; OmadaEnabled = $true; DebounceMilliseconds = 400 }
    function Get-SqlValidationSetting { return $script:Setting }

    $script:Stopped = [System.Collections.Generic.List[object]]::new()
    function Stop-SqlDiagnosticBackground {
        param($TabSession)
        $script:Stopped.Add($TabSession)
    }

    # A stand-in for the DispatcherTimer: Request-SqlSyntaxValidation only stops, sets the interval
    # and starts it again.
    function New-FakeTimer {
        $Timer = [PSCustomObject]@{ Starts = 0; Interval = $null }
        $Timer | Add-Member -MemberType ScriptMethod -Name Stop -Value { }
        $Timer | Add-Member -MemberType ScriptMethod -Name Start -Value { $this.Starts++ }
        return $Timer
    }
}

Describe 'Invoke-EditorContentChanged' -Tag 'Unit' {

    BeforeEach {
        $script:HeaderRefreshes = 0
        $script:Stopped.Clear()
        $Script:SqlValidationDebounceTimer = New-FakeTimer
        $script:Setting.Enabled = $true
    }

    It 'Should mark a clean tab dirty and refresh its header once' {
        $Tab = [PSCustomObject]@{ Id = "a"; IsDirty = $false }

        Invoke-EditorContentChanged -TabSession $Tab

        $Tab.IsDirty | Should -BeTrue
        $script:HeaderRefreshes | Should -Be 1
    }

    It 'Should not rebuild the header on every further keystroke' {
        # The header shows "*" for unsaved changes and nothing else in it depends on the text, so once
        # the tab is dirty another refresh produces the same title.
        $Tab = [PSCustomObject]@{ Id = "a"; IsDirty = $false }

        1..25 | ForEach-Object { Invoke-EditorContentChanged -TabSession $Tab }

        $script:HeaderRefreshes | Should -Be 1
    }

    It 'Should refresh the header again after a save made the tab clean' {
        $Tab = [PSCustomObject]@{ Id = "a"; IsDirty = $false }
        Invoke-EditorContentChanged -TabSession $Tab
        $Tab.IsDirty = $false

        Invoke-EditorContentChanged -TabSession $Tab

        $script:HeaderRefreshes | Should -Be 2
    }

    It 'Should push the validation debounce forward on every keystroke' {
        $Tab = [PSCustomObject]@{ Id = "a"; IsDirty = $true }

        1..3 | ForEach-Object { Invoke-EditorContentChanged -TabSession $Tab }

        $Script:SqlValidationDebounceTimer.Starts | Should -Be 3
        $Script:SqlValidationPendingTabId | Should -Be "a"
    }

    It 'Should do nothing for a message without a tab' {
        { Invoke-EditorContentChanged -TabSession $null } | Should -Not -Throw
        $script:HeaderRefreshes | Should -Be 0
    }
}
