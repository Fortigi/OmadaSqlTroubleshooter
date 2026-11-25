function Update-MainMenuState {
    <#
    .SYNOPSIS
        Brings a menu bar menu's items in line with the active tab, as the menu opens.

    .DESCRIPTION
        Read when the menu opens rather than kept in step: the toolbar buttons belong to each tab and
        change state in many places, while the menu is only seen when it is open. See
        Resolve-MainMenuItemState for what each item mirrors.

    .PARAMETER MenuItem
        The top-level menu that is opening.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $MenuItem
    )

    $Private:Tab = Get-ActiveTabSession
    $Private:Elements = if ($null -ne $Private:Tab) { $Private:Tab.Elements } else { $null }
    $Private:Items = @($MenuItem.Items | Where-Object { $_.Tag -is [string] -and $_.Tag -match ":" })

    # Asked only for the menu that has the item (Help), and answered from the session's cache after
    # the first time.
    $Private:ReleaseLink = $null
    if (@($Private:Items | Where-Object { $_.Tag -eq "App:ReleaseNotes" }).Count -gt 0) {
        $Private:ReleaseLink = Get-GitHubReleaseLink
    }

    $Private:ResultItems = @{}
    if (@($Private:Items | Where-Object { $_.Tag -like "Result:*" }).Count -gt 0) {
        Update-DataGridQueryResultContextMenuState
        $Private:ResultItems = Get-MainMenuResultItem
    }

    foreach ($Private:Item in $Private:Items) {
        $Private:State = Resolve-MainMenuItemState -Tag $Private:Item.Tag -Elements $Private:Elements -ResultMenuItem $Private:ResultItems -TabCount @($Script:Tabs).Count -ReleaseLink $Private:ReleaseLink
        Set-MainMenuItemState -Item $Private:Item -State $Private:State
    }
}

function Set-MainMenuItemState {
    <#
    .SYNOPSIS
        Applies a Resolve-MainMenuItemState answer to a menu item. IsChecked, IsVisible and Header are
        left as they are when the answer has none for them.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Item,

        [Parameter(Mandatory = $true)]
        $State
    )

    $Item.IsEnabled = $State.IsEnabled
    if ($null -ne $State.IsChecked) {
        $Item.IsChecked = $State.IsChecked
    }
    if ($null -ne $State.IsVisible) {
        $Item.Visibility = if ($State.IsVisible) { "Visible" } else { "Collapsed" }
    }
    if (![string]::IsNullOrWhiteSpace($State.Header)) {
        $Item.Header = $State.Header
    }
}
