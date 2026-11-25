function Resolve-MainMenuItemState {
    <#
    .SYNOPSIS
        What one menu bar item should look like right now: enabled, checked, and its header.

    .DESCRIPTION
        The menu bar belongs to the window, the commands to the active tab (each tab has its own
        toolbar and state), so an item mirrors what it runs:

          Button:<Name>   the active tab's toolbar button: enabled exactly when it is. Connect and
                          Execute also take the button's current text, which flips to Disconnect /
                          Cancel.
          Check:<Name>    the active tab's filter checkbox: enabled and checked as it is.
          Result:<Name>   the result grid's context menu item, after its state was refreshed for the
                          focused result (Update-DataGridQueryResultContextMenuState).
          Tab:<Action>    the tab commands: New always; Next, Previous and Close others need a second
                          tab; the rest need an active tab.
          Action:<Name>   a command on the active tab: needs one.
          App:<Name>      Exit, About, Help, Report a bug, Request a feature: always.
                          ReleaseNotes: shown, enabled and named after the release only with a
                          -ReleaseLink (Resolve-MainMenuAppItemState).

        Pure: no WPF, so every rule is tested.

    .PARAMETER Tag
        The item's Tag.

    .PARAMETER Elements
        The active tab's elements, or $null without a tab.

    .PARAMETER ResultMenuItem
        The result grid's context menu items, by name.

    .PARAMETER TabCount
        How many tabs are open.

    .PARAMETER ReleaseLink
        The running version's GitHub release page, or $null when there is none (Get-GitHubReleaseLink).

    .OUTPUTS
        [PSCustomObject] @{ IsEnabled; IsChecked; Header; IsVisible } - IsChecked, Header and IsVisible
        $null when the item has none to set.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tag,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Elements,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [hashtable]$ResultMenuItem = @{},

        [int]$TabCount = 0,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ReleaseLink
    )

    $Private:Kind, $Private:Name = $Tag -split ":", 2
    $Private:State = [PSCustomObject]@{ IsEnabled = $false; IsChecked = $null; Header = $null; IsVisible = $null }
    $Private:HasTab = $null -ne $Elements

    switch ($Private:Kind) {
        "Button" {
            $Private:State.IsEnabled = $Private:HasTab -and [bool]$Elements.$Private:Name.IsEnabled
            if ($Private:Name -in @("ButtonConnect", "ButtonExecuteQuery") -and $Private:HasTab) {
                $Private:TextName = "{0}Text" -f $Private:Name
                $Private:State.Header = [string]$Elements.$Private:TextName.Text
            }
        }
        "Check" {
            $Private:State.IsEnabled = $Private:HasTab -and [bool]$Elements.$Private:Name.IsEnabled
            $Private:State.IsChecked = $Private:HasTab -and [bool]$Elements.$Private:Name.IsChecked
        }
        "Result" {
            # The two "Copy as" items sit in the context menu's Copy As submenu, whose parent is the
            # item that context menu enables; they follow it.
            $Private:Gate = if ($Private:Name -like "CopyAs?*") { "CopyAs" } else { $Private:Name }
            $Private:State.IsEnabled = $null -ne $ResultMenuItem -and [bool]$ResultMenuItem[$Private:Gate].IsEnabled
        }
        "Tab" {
            $Private:State.IsEnabled = Test-MainMenuTabActionEnabled -Action $Private:Name -HasTab $Private:HasTab -TabCount $TabCount
        }
        "Action" {
            $Private:State.IsEnabled = $Private:HasTab
        }
        "App" {
            Resolve-MainMenuAppItemState -State $Private:State -Name $Private:Name -ReleaseLink $ReleaseLink
        }
    }

    return $Private:State
}

function Resolve-MainMenuAppItemState {
    <#
    .SYNOPSIS
        Sets the state of an App: item: always enabled, except Release notes, which is shown, enabled
        and named after the release (its tag, the last part of the page address) only when there is
        one.

    .OUTPUTS
        None. -State is changed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $State,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ReleaseLink
    )

    if ($Name -ne "ReleaseNotes") {
        $State.IsEnabled = $true
        return
    }

    $Private:HasRelease = -not [string]::IsNullOrWhiteSpace($ReleaseLink)
    $State.IsEnabled = $Private:HasRelease
    $State.IsVisible = $Private:HasRelease
    if ($Private:HasRelease) {
        $State.Header = "_Release notes for {0} on GitHub" -f ($ReleaseLink -split "/")[-1]
    }
}

function Test-MainMenuTabActionEnabled {
    <#
    .SYNOPSIS
        Whether a Window menu tab command can run: New always, switching and Close others with a
        second tab, the rest with an active tab.

    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,

        [bool]$HasTab,

        [int]$TabCount
    )

    if ($Action -eq "New") {
        return $true
    }
    if ($Action -in @("Next", "Previous", "CloseOthers")) {
        return $HasTab -and $TabCount -gt 1
    }
    return $HasTab
}
