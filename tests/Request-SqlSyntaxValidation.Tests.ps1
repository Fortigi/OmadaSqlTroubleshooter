#Requires -Version 7.0
# Tests for scheduling the debounced validation, which runs on every keystroke (issue #185).

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Script:PrivatePath = [System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private")

    . (Join-Path $Script:PrivatePath "Request-SqlSyntaxValidation.ps1")

    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$Message, [string]$LogType = "INFO", $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
        process { }
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

Describe 'Request-SqlSyntaxValidation' -Tag 'Unit' {

    BeforeEach {
        $script:Stopped.Clear()
        $Script:SqlValidationDebounceTimer = New-FakeTimer
        $script:Setting.Enabled = $true
        $script:Setting.SchemaEnabled = $true
        $script:Setting.OmadaEnabled = $true
    }

    It 'Should stop the tab''s running validation, because the text it is checking has just changed' {
        # Otherwise markers for the text as it was a keystroke ago could appear after this one.
        $Tab = [PSCustomObject]@{ Id = "a" }

        Request-SqlSyntaxValidation -TabSession $Tab

        $script:Stopped.Count | Should -Be 1
        $script:Stopped[0] | Should -Be $Tab
    }

    It 'Should leave everything alone when validation is switched off' {
        $script:Setting.Enabled = $false
        $script:Setting.SchemaEnabled = $false
        $script:Setting.OmadaEnabled = $false

        Request-SqlSyntaxValidation -TabSession ([PSCustomObject]@{ Id = "a" })

        $script:Stopped.Count | Should -Be 0
        $Script:SqlValidationDebounceTimer.Starts | Should -Be 0
    }
}
