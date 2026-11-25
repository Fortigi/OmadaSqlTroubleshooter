#Requires -Version 7.0
BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Stop-ApplicationTimer.ps1")

    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)]$Message, $LogType) process { } }

    function script:New-FakeTimer {
        param([switch]$Throws)
        $Timer = [PSCustomObject]@{ Stopped = 0; Throws = [bool]$Throws }
        $Timer | Add-Member -MemberType ScriptMethod -Name Stop -Value { if ($this.Throws) { throw "gone" }; $this.Stopped++ }
        $Timer
    }
}

Describe 'Stop-ApplicationTimer' -Tag 'Unit' {
    It 'Should stop every application timer and let go of it' {
        $Poll = New-FakeTimer
        $Debounce = New-FakeTimer
        $Schema = New-FakeTimer
        $Watchdog = New-FakeTimer
        $Script:WebViewCompletionPollTimer = $Poll
        $Script:SqlValidationDebounceTimer = $Debounce
        $Script:SqlSchemaFilterTimer = $Schema
        $Script:E2EWatchdog = $Watchdog

        Stop-ApplicationTimer | Should -Be 4

        @($Poll, $Debounce, $Schema, $Watchdog).Stopped | Should -Be @(1, 1, 1, 1)
        $Script:WebViewCompletionPollTimer | Should -BeNullOrEmpty
        $Script:SqlValidationDebounceTimer | Should -BeNullOrEmpty
        $Script:SqlSchemaFilterTimer | Should -BeNullOrEmpty
        $Script:E2EWatchdog | Should -BeNullOrEmpty
    }

    It 'Should skip timers that were never started' {
        $Script:WebViewCompletionPollTimer = New-FakeTimer
        $Script:SqlValidationDebounceTimer = $null
        $Script:SqlSchemaFilterTimer = $null
        Remove-Variable -Scope Script -Name E2EWatchdog -ErrorAction SilentlyContinue

        Stop-ApplicationTimer | Should -Be 1
    }

    It 'Should still let go of a timer that cannot be stopped, and stop the others' {
        $Other = New-FakeTimer
        $Script:WebViewCompletionPollTimer = New-FakeTimer -Throws
        $Script:SqlValidationDebounceTimer = $Other
        $Script:SqlSchemaFilterTimer = $null
        $Script:E2EWatchdog = $null

        Stop-ApplicationTimer | Should -Be 1

        $Other.Stopped | Should -Be 1
        $Script:WebViewCompletionPollTimer | Should -BeNullOrEmpty
    }

    It 'Should be safe to call twice, as it is at the end of a run and at the start of the next' {
        $Script:WebViewCompletionPollTimer = New-FakeTimer

        $null = Stop-ApplicationTimer
        Stop-ApplicationTimer | Should -Be 0
    }
}
