#Requires -Version 7.0
# Since queries run in the background (issue #40) a failure can arrive for a tab the user is not
# looking at. A modal about an invisible query interrupts work on the tab they ARE looking at, and
# because it is modal they cannot carry on until they dismiss something irrelevant to them. So a
# tab-scoped message raised off screen is held and shown when that tab is next opened.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Add-TabScopedMessage.ps1")
    . (Join-Path $PrivatePath -ChildPath "Test-ActiveTabIsOnScreen.ps1")

    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog)
        process { }
    }

    $script:ShownDialogs = [System.Collections.Generic.List[object]]::new()
    function Show-LogMessageDialog {
        param([string]$Text, [string]$Title, $Icon)
        $script:ShownDialogs.Add([pscustomobject]@{ Text = $Text; Title = $Title; Icon = $Icon })
    }

    function script:New-FakeTab {
        param([string]$Id)
        return [pscustomobject]@{
            Id              = $Id
            DisplayName     = $Id
            TabItem         = "item-$Id"
            PendingMessages = [System.Collections.Generic.List[object]]::new()
        }
    }

    function script:Initialize-MessageTestState {
        $script:ShownDialogs.Clear()
        $Script:TabA = New-FakeTab -Id "A"
        $Script:TabB = New-FakeTab -Id "B"
        $Script:ActiveTabForTest = $Script:TabA
        $Script:SelectedTabItem = $Script:TabA.TabItem
    }

    function Get-ActiveTabSession { return $Script:ActiveTabForTest }
    function Get-TabControlSessions { return [pscustomobject]@{ SelectedItem = $Script:SelectedTabItem } }
}

Describe "Test-ActiveTabIsOnScreen" {
    BeforeEach { Initialize-MessageTestState }

    It "is true when the acting tab is the one being looked at" {
        Test-ActiveTabIsOnScreen | Should -BeTrue
    }

    It "is false when a completion is acting for a tab that is off screen" {
        # The poll timer steps into the owning tab to run its completion, so the acting tab and the
        # visible tab genuinely differ - which is precisely when a modal must not appear.
        $Script:SelectedTabItem = $Script:TabB.TabItem

        Test-ActiveTabIsOnScreen | Should -BeFalse
    }

    It "is true when there is no tab context at all" {
        $Script:ActiveTabForTest = $null

        Test-ActiveTabIsOnScreen | Should -BeTrue
    }

    It "fails towards showing the message when the question cannot be answered" {
        # Holding a message back because this check threw would lose it until the user happened to
        # switch tabs. Showing it once too often is the better failure.
        Mock Get-TabControlSessions { throw "no tab control" }

        Test-ActiveTabIsOnScreen | Should -BeTrue
    }
}

Describe "Add-TabScopedMessage" {
    BeforeEach { Initialize-MessageTestState }

    It "holds the message on the tab it belongs to" {
        Add-TabScopedMessage -TabSession $Script:TabA -Text "boom" -Title "Error - A" -Icon "Error"

        @($Script:TabA.PendingMessages).Count | Should -Be 1
        @($Script:TabB.PendingMessages).Count | Should -Be 0
    }

    It "shows nothing at the time it is held" {
        Add-TabScopedMessage -TabSession $Script:TabA -Text "boom" -Title "Error - A" -Icon "Error"

        @($script:ShownDialogs).Count | Should -Be 0
    }

    It "caps the backlog so a repeatedly failing tab cannot pile up" {
        1..15 | ForEach-Object { Add-TabScopedMessage -TabSession $Script:TabA -Text "boom $_" -Title "Error - A" -Icon "Error" }

        @($Script:TabA.PendingMessages).Count | Should -Be 10
        # Oldest dropped: the most recent failure describes the current state.
        $Script:TabA.PendingMessages[-1].Text | Should -Be "boom 15"
    }

    It "is safe with no tab" {
        { Add-TabScopedMessage -TabSession $null -Text "boom" -Title "t" -Icon "Error" } | Should -Not -Throw
    }
}

Describe "Show-TabScopedMessage" {
    BeforeEach { Initialize-MessageTestState }

    It "shows what was held when the tab is opened" {
        Add-TabScopedMessage -TabSession $Script:TabA -Text "boom" -Title "Error - A" -Icon "Error"

        Show-TabScopedMessage -TabSession $Script:TabA

        @($script:ShownDialogs).Count | Should -Be 1
        $script:ShownDialogs[0].Text | Should -Match "boom"
        $script:ShownDialogs[0].Title | Should -Be "Error - A"
    }

    It "coalesces several into one dialog" {
        # Opening a tab that failed four times must not mean dismissing four modals in a row.
        1..4 | ForEach-Object { Add-TabScopedMessage -TabSession $Script:TabA -Text "boom $_" -Title "Error - A" -Icon "Error" }

        Show-TabScopedMessage -TabSession $Script:TabA

        @($script:ShownDialogs).Count | Should -Be 1
        $script:ShownDialogs[0].Text | Should -Match "4 messages occurred"
        $script:ShownDialogs[0].Text | Should -Match "boom 1"
        $script:ShownDialogs[0].Text | Should -Match "boom 4"
    }

    It "empties the queue, so re-opening the tab does not show it again" {
        Add-TabScopedMessage -TabSession $Script:TabA -Text "boom" -Title "Error - A" -Icon "Error"

        Show-TabScopedMessage -TabSession $Script:TabA
        Show-TabScopedMessage -TabSession $Script:TabA

        @($script:ShownDialogs).Count | Should -Be 1
    }

    It "clears the queue before showing, so a message enqueued by the modal's own pump survives" {
        # A modal pumps the dispatcher, which lets the completion poll timer run, which can enqueue
        # another message for this same tab. Clearing afterwards would discard it unseen.
        Add-TabScopedMessage -TabSession $Script:TabA -Text "first" -Title "Error - A" -Icon "Error"
        Mock Show-LogMessageDialog {
            $script:ShownDialogs.Add([pscustomobject]@{ Text = $Text; Title = $Title; Icon = $Icon })
            Add-TabScopedMessage -TabSession $Script:TabA -Text "arrived during the modal" -Title "Error - A" -Icon "Error"
        }

        Show-TabScopedMessage -TabSession $Script:TabA

        @($Script:TabA.PendingMessages).Count | Should -Be 1
        $Script:TabA.PendingMessages[0].Text | Should -Be "arrived during the modal"
    }

    It "does nothing when there is nothing held" {
        Show-TabScopedMessage -TabSession $Script:TabA

        @($script:ShownDialogs).Count | Should -Be 0
    }

    It "does not show another tab's messages" {
        Add-TabScopedMessage -TabSession $Script:TabB -Text "B failed" -Title "Error - B" -Icon "Error"

        Show-TabScopedMessage -TabSession $Script:TabA

        @($script:ShownDialogs).Count | Should -Be 0
        @($Script:TabB.PendingMessages).Count | Should -Be 1
    }
}
