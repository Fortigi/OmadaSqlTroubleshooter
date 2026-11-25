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

    $Private:ResultItems = @{}
    if (@($Private:Items | Where-Object { $_.Tag -like "Result:*" }).Count -gt 0) {
        Update-DataGridQueryResultContextMenuState
        $Private:ResultItems = Get-MainMenuResultItem
    }

    foreach ($Private:Item in $Private:Items) {
        $Private:State = Resolve-MainMenuItemState -Tag $Private:Item.Tag -Elements $Private:Elements -ResultMenuItem $Private:ResultItems -TabCount @($Script:Tabs).Count
        $Private:Item.IsEnabled = $Private:State.IsEnabled
        if ($null -ne $Private:State.IsChecked) {
            $Private:Item.IsChecked = $Private:State.IsChecked
        }
        if (![string]::IsNullOrWhiteSpace($Private:State.Header)) {
            $Private:Item.Header = $Private:State.Header
        }
    }
}
