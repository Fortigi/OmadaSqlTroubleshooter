#Requires -Version 7.0
# Set-ActiveTabContext repoints the "current tab" globals, and it serves two callers that look alike
# and are not: a REAL tab switch (TabControlSessions.SelectionChanged) and a completion callback
# "stepping into" a tab to run its continuation before stepping back out.
#
# The asymmetry these tests exist for (issue #165): the save at the top of the function is skipped
# when the incoming tab is already the active one, while the restore of the scalars ran
# unconditionally. So stepping into the ACTIVE tab overwrote a live $Script:Task with that tab's
# stored PendingTask - seeded $null by New-TabSession and only written when an editor task STARTS -
# and the in-flight task was lost.
#
# Why it was invisible: an editor read whose task has been replaced never produces a result, which is
# indistinguishable from one that was never requested. It surfaced as validation markers that were
# simply never pushed, in a suite where the only visible symptom was an assertion about
# setDiagnostics. Latent until something put enough completions on the queue to land inside that
# window, which the schema fan-out of #165 does.
#
# Initialize-UiComponents is stubbed: it resolves the WPF context menu, which the headless lane
# cannot load. Everything else here is plain objects.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Set-ActiveTabContext.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { }
    }

    function ConvertTo-RedactedLogString { param($InputObject, $MaxDepth, [switch]$ShapeOnly) return "<redacted>" }

    $script:UiRebindCount = 0
    function Initialize-UiComponents { $script:UiRebindCount++ }

    function script:New-TestTab {
        param([string]$Id, [string]$Url, [bool]$Connected, $PendingTask)

        return [pscustomobject]@{
            Id               = $Id
            DisplayName      = "Tab $Id"
            Elements         = [pscustomobject]@{ Marker = "elements-$Id" }
            RunTimeData      = [pscustomobject]@{ Marker = "runtime-$Id" }
            WebView          = [pscustomobject]@{ Marker = "webview-$Id" }
            AppConfig        = [pscustomobject]@{ Marker = "config-$Id" }
            ConnectionStatus = $Connected
            PendingTask      = $PendingTask
            CurrentUrl       = $Url
        }
    }

    function script:Reset-TabState {
        $script:TabA = New-TestTab -Id "tab-a" -Url "https://a.example" -Connected $true -PendingTask "stored-task-a"
        $script:TabB = New-TestTab -Id "tab-b" -Url "https://b.example" -Connected $false -PendingTask "stored-task-b"

        $Script:Tabs = @($script:TabA, $script:TabB)
        $Script:MainForm = [pscustomobject]@{ Elements = $null }
        $Script:RunTimeConfig = [pscustomobject]@{ ApplicationName = "Test" }

        $Script:ActiveTabId = $null
        $Script:Task = $null
        $Script:ConnectionStatus = $false
        $Script:CurrentUrl = $null
        $script:UiRebindCount = 0
    }
}

Describe "Set-ActiveTabContext - a real tab switch" {

    BeforeEach {
        Reset-TabState
    }

    It "points every current-tab global at the incoming tab" {
        Set-ActiveTabContext -TabSession $script:TabA

        $Script:MainForm.Elements.Marker | Should -BeExactly "elements-tab-a"
        $Script:RunTimeData.Marker | Should -BeExactly "runtime-tab-a"
        $Script:WebView.Marker | Should -BeExactly "webview-tab-a"
        $Script:AppConfig.Marker | Should -BeExactly "config-tab-a"
        $Script:ActiveTabId | Should -BeExactly "tab-a"
    }

    It "restores the incoming tab's scalars" {
        Set-ActiveTabContext -TabSession $script:TabA

        $Script:Task | Should -BeExactly "stored-task-a"
        $Script:ConnectionStatus | Should -BeTrue
        $Script:CurrentUrl | Should -BeExactly "https://a.example"
    }

    It "saves the outgoing tab's live scalars before switching away" {
        # The half of the pairing that does work, and the reason the restore exists at all: a tab
        # switched away from must remember what it was doing.
        Set-ActiveTabContext -TabSession $script:TabA
        $Script:Task = "live-task-a"
        $Script:ConnectionStatus = $false
        $Script:CurrentUrl = "https://a.example/changed"

        Set-ActiveTabContext -TabSession $script:TabB

        $script:TabA.PendingTask | Should -BeExactly "live-task-a"
        $script:TabA.ConnectionStatus | Should -BeFalse
        $script:TabA.CurrentUrl | Should -BeExactly "https://a.example/changed"
    }

    It "then restores the tab it switched to" {
        Set-ActiveTabContext -TabSession $script:TabA
        Set-ActiveTabContext -TabSession $script:TabB

        $Script:Task | Should -BeExactly "stored-task-b"
        $Script:ConnectionStatus | Should -BeFalse
        $Script:CurrentUrl | Should -BeExactly "https://b.example"
    }

    It "rebinds the per-tab UI components" {
        Set-ActiveTabContext -TabSession $script:TabA

        $script:UiRebindCount | Should -Be 1
    }
}

Describe "Set-ActiveTabContext - stepping into the tab that is already active" {
    # What a background completion does on its way to running a continuation. The tab does not
    # change, so there is nothing to restore - and restoring anyway destroys live state.

    BeforeEach {
        Reset-TabState
        Set-ActiveTabContext -TabSession $script:TabA
    }

    It "does not replace a live editor task with the tab's stored one" {
        # THE regression test for issue #165. Invoke-ExecuteScriptAsync writes PendingTask when a task
        # STARTS, so the live $Script:Task is the newer value; the save above is skipped for the same
        # tab, so restoring the stored copy here loses it outright.
        $Script:Task = "live-task-in-flight"

        Set-ActiveTabContext -TabSession $script:TabA

        $Script:Task | Should -BeExactly "live-task-in-flight"
    }

    It "does not lose a task when the stored value is null, which is how a tab starts" {
        # The exact shape of the defect: New-TabSession seeds PendingTask $null, so the clobber
        # replaced a real task with nothing and the editor read never produced a result.
        $script:TabA.PendingTask = $null
        $Script:Task = "live-task-in-flight"

        Set-ActiveTabContext -TabSession $script:TabA

        $Script:Task | Should -BeExactly "live-task-in-flight"
    }

    It "does not overwrite the live connection status" {
        # Set-SqlConnectionState writes the live flag; the stored copy is only updated when the tab is
        # switched away from, so it can be arbitrarily stale.
        $Script:ConnectionStatus = $false
        $script:TabA.ConnectionStatus = $true

        Set-ActiveTabContext -TabSession $script:TabA

        $Script:ConnectionStatus | Should -BeFalse
    }

    It "does not overwrite the live current url" {
        $Script:CurrentUrl = "https://a.example/live"

        Set-ActiveTabContext -TabSession $script:TabA

        $Script:CurrentUrl | Should -BeExactly "https://a.example/live"
    }

    It "still rebinds the UI components, which the completion relies on" {
        # Not an optimisation: the menu items are resolved per tab, and a completion that acts on the
        # grid needs them bound even when the tab did not change.
        $script:UiRebindCount = 0

        Set-ActiveTabContext -TabSession $script:TabA

        $script:UiRebindCount | Should -Be 1
    }

    It "leaves the object references pointing at the same tab" {
        Set-ActiveTabContext -TabSession $script:TabA

        $Script:RunTimeData.Marker | Should -BeExactly "runtime-tab-a"
        $Script:ActiveTabId | Should -BeExactly "tab-a"
    }
}

Describe "Set-ActiveTabContext - the first call of a session" {

    BeforeEach {
        Reset-TabState
    }

    It "restores the scalars when there is no active tab yet" {
        # $Script:ActiveTabId is $null at start-up, which must not be mistaken for "already active".
        $Script:Task = "leftover"

        Set-ActiveTabContext -TabSession $script:TabA

        $Script:Task | Should -BeExactly "stored-task-a"
    }
}
