#Requires -Version 7.0
# Two reported symptoms, one cause: $Script:PopupWindowExecuteQuery was a single module-scope slot
# that Set-ActiveTabContext does NOT repoint, so it was shared by every tab. The window is owned by
# the main form, so it floated over tabs that were not running anything - and a second execute
# overwrote the slot, orphaning the first window so that nothing could ever close it.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Show-ExecuteQueryPopup.ps1")

    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog)
        process { }
    }

    # A stand-in for the WPF window that records what was asked of it, so the tests can assert on
    # visibility without a display.
    function script:New-FakePopup {
        $Popup = [pscustomobject]@{ Visible = $false; Closed = $false }
        $Popup | Add-Member -MemberType ScriptMethod -Name Show -Value { $this.Visible = $true } -Force
        $Popup | Add-Member -MemberType ScriptMethod -Name Hide -Value { $this.Visible = $false } -Force
        $Popup | Add-Member -MemberType ScriptMethod -Name Close -Value { $this.Closed = $true; $this.Visible = $false } -Force
        return $Popup
    }

    function script:New-FakeTab {
        param([string]$Id)
        return [pscustomobject]@{ Id = $Id; DisplayName = $Id; TabItem = [pscustomobject]@{ Name = $Id }; ExecutePopup = $null }
    }

    function Show-PopupWindow { param($Message) return New-FakePopup }

    function script:Initialize-PopupTestState {
        $Script:TabA = New-FakeTab -Id "A"
        $Script:TabB = New-FakeTab -Id "B"
        $Script:Tabs = @($Script:TabA, $Script:TabB)
        $Script:SelectedTabItem = $Script:TabA.TabItem
        $Script:ActiveTabForTest = $Script:TabA
    }

    function Get-TabControlSessions { return [pscustomobject]@{ SelectedItem = $Script:SelectedTabItem } }
    function Get-ActiveTabSession { return $Script:ActiveTabForTest }
}

Describe "Show-ExecuteQueryPopup" {
    BeforeEach { Initialize-PopupTestState }

    It "puts the popup on the tab that started the query, not in module scope" {
        Show-ExecuteQueryPopup

        $Script:TabA.ExecutePopup | Should -Not -BeNullOrEmpty
        $Script:TabB.ExecutePopup | Should -BeNullOrEmpty
    }

    It "does not replace a popup the tab already has" {
        # Replacing it is what orphaned windows: the old object was dropped, so nothing could close it.
        Show-ExecuteQueryPopup
        $Private:First = $Script:TabA.ExecutePopup

        Show-ExecuteQueryPopup

        $Script:TabA.ExecutePopup | Should -Be $Private:First
        $Private:First.Closed | Should -BeFalse
    }

    It "gives each tab its own popup" {
        Show-ExecuteQueryPopup
        $Script:ActiveTabForTest = $Script:TabB
        Show-ExecuteQueryPopup

        $Script:TabA.ExecutePopup | Should -Not -Be $Script:TabB.ExecutePopup
    }
}

Describe "Sync-ExecuteQueryPopupVisibility" {
    BeforeEach { Initialize-PopupTestState }

    It "hides the popup of a tab that is not on screen" {
        # The reported symptom: switching to a tab that is not running anything still showed
        # "Executing Query...".
        Show-ExecuteQueryPopup
        $Script:TabA.ExecutePopup.Visible | Should -BeTrue

        $Script:SelectedTabItem = $Script:TabB.TabItem
        Sync-ExecuteQueryPopupVisibility

        $Script:TabA.ExecutePopup.Visible | Should -BeFalse
    }

    It "shows it again when the user switches back" {
        Show-ExecuteQueryPopup
        $Script:SelectedTabItem = $Script:TabB.TabItem
        Sync-ExecuteQueryPopupVisibility

        $Script:SelectedTabItem = $Script:TabA.TabItem
        Sync-ExecuteQueryPopupVisibility

        $Script:TabA.ExecutePopup.Visible | Should -BeTrue
    }

    It "leaves tabs with no popup alone" {
        { Sync-ExecuteQueryPopupVisibility } | Should -Not -Throw
        $Script:TabB.ExecutePopup | Should -BeNullOrEmpty
    }

    It "shows only the selected tab's popup when two tabs are executing" {
        Show-ExecuteQueryPopup
        $Script:ActiveTabForTest = $Script:TabB
        Show-ExecuteQueryPopup

        $Script:SelectedTabItem = $Script:TabB.TabItem
        Sync-ExecuteQueryPopupVisibility

        $Script:TabA.ExecutePopup.Visible | Should -BeFalse
        $Script:TabB.ExecutePopup.Visible | Should -BeTrue
    }
}

Describe "Close-ExecuteQueryPopup" {
    BeforeEach { Initialize-PopupTestState }

    It "closes the owning tab's popup and clears the slot" {
        Show-ExecuteQueryPopup
        $Private:Popup = $Script:TabA.ExecutePopup

        Close-ExecuteQueryPopup

        $Private:Popup.Closed | Should -BeTrue
        $Script:TabA.ExecutePopup | Should -BeNullOrEmpty
    }

    It "does not touch another tab's popup" {
        Show-ExecuteQueryPopup
        $Script:ActiveTabForTest = $Script:TabB
        Show-ExecuteQueryPopup

        Close-ExecuteQueryPopup

        $Script:TabB.ExecutePopup | Should -BeNullOrEmpty
        $Script:TabA.ExecutePopup | Should -Not -BeNullOrEmpty
        $Script:TabA.ExecutePopup.Closed | Should -BeFalse
    }

    It "can close a specific tab's popup regardless of which tab is active" {
        Show-ExecuteQueryPopup
        $Private:Popup = $Script:TabA.ExecutePopup
        $Script:ActiveTabForTest = $Script:TabB

        Close-ExecuteQueryPopup -TabSession $Script:TabA

        $Private:Popup.Closed | Should -BeTrue
    }

    It "is safe to call when there is nothing to close" {
        { Close-ExecuteQueryPopup } | Should -Not -Throw
    }
}
