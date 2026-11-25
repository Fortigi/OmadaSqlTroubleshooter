function Invoke-MainMenuAction {
    <#
    .SYNOPSIS
        Runs the command a menu bar item stands for, on the active tab.

    .DESCRIPTION
        Every command already has its implementation - a toolbar button's click handler, a result
        grid context menu item, a tab context menu function - so the menu runs exactly that rather
        than a copy: a button or menu item is clicked (Invoke-ElementClick), which runs the very
        handler the toolbar or the context menu runs, with the same checks. A disabled one is not
        clicked; the menu showed it disabled anyway (Update-MainMenuState).

        See Resolve-MainMenuItemState for the Tag forms.

    .PARAMETER Tag
        The menu item's Tag.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tag
    )

    $Private:Kind, $Private:Name = $Tag -split ":", 2
    "Menu: {0}" -f $Tag | Write-LogOutput -LogType DEBUG

    switch ($Private:Kind) {
        "Button" {
            $Private:Button = $Script:MainForm.Elements.$Private:Name
            if ($null -ne $Private:Button -and $Private:Button.IsEnabled) {
                Invoke-ElementClick -Element $Private:Button
            }
        }
        "Check" {
            # Toggling raises the checkbox's own Checked / Unchecked handlers, which apply the filter.
            $Private:CheckBox = $Script:MainForm.Elements.$Private:Name
            if ($null -ne $Private:CheckBox -and $Private:CheckBox.IsEnabled) {
                $Private:CheckBox.IsChecked = -not [bool]$Private:CheckBox.IsChecked
            }
        }
        "Result" {
            $Private:Item = (Get-MainMenuResultItem)[$Private:Name]
            if ($null -ne $Private:Item -and $Private:Item.IsEnabled) {
                Invoke-ElementClick -Element $Private:Item
            }
        }
        "Tab" {
            Invoke-MainMenuTabAction -Action $Private:Name
        }
        "Action" {
            Set-TabResultOutputMode -TabSession (Get-ActiveTabSession) -Mode ($Private:Name -replace "^ResultsTo", "")
        }
        "App" {
            Invoke-MainMenuAppAction -Action $Private:Name
        }
    }
}

function Invoke-MainMenuTabAction {
    <#
    .SYNOPSIS
        The Window menu's tab commands: the same functions the tab header's context menu and the
        keyboard shortcuts call, for the active tab.

    .PARAMETER Action
        New, Duplicate, DuplicateWithoutQuery, Next, Previous, Close, CloseOthers or CloseAll.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("New", "Duplicate", "DuplicateWithoutQuery", "Next", "Previous", "Close", "CloseOthers", "CloseAll")]
        [string]$Action
    )

    $Private:TabId = $Script:ActiveTabId
    switch ($Action) {
        "New" { $null = New-EmptyTabSession }
        "Duplicate" { Invoke-DuplicateTab -TabId $Private:TabId }
        "DuplicateWithoutQuery" { Invoke-DuplicateTab -TabId $Private:TabId -WithoutQuery }
        "Next" { Select-AdjacentTab -Direction Next }
        "Previous" { Select-AdjacentTab -Direction Previous }
        "Close" { Close-TabSession -TabId $Private:TabId }
        "CloseOthers" { Close-OtherTabSessions -KeepTabId $Private:TabId }
        "CloseAll" { Close-AllTabSessions }
    }
}

function Invoke-MainMenuAppAction {
    <#
    .SYNOPSIS
        The application commands of the File and Help menus.

    .PARAMETER Action
        Exit, About, Help, ReportBug, RequestFeature or ReleaseNotes.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Exit", "About", "Help", "ReportBug", "RequestFeature", "ReleaseNotes")]
        [string]$Action
    )

    switch ($Action) {
        "Exit" { $Script:MainForm.Definition.Close() }
        "About" { Open-AboutForm }
        "Help" { Open-HelpForm }
        "ReportBug" { Open-GitHubIssue -Kind Bug }
        "RequestFeature" { Open-GitHubIssue -Kind Feature }
        "ReleaseNotes" { Open-GitHubReleaseNotes }
    }
}

function Get-MainMenuResultItem {
    <#
    .SYNOPSIS
        The result grid's context menu items, by the name the menu bar's Result: tags use.

    .DESCRIPTION
        Initialize-UiComponents resolves them from the shared context menu into the
        $Script:DataGridQueryResultMenuItem* variables; their click handlers act on whichever result
        has focus, which is what the menu bar needs too.

    .OUTPUTS
        [hashtable]
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $Private:Items = @{}
    foreach ($Private:Name in @("Copy", "CopyWithHeader", "CopyAs", "CopyAsSqlArray", "CopyAsPowerShellArray", "SelectAll", "SaveAs", "SaveSelectedAs", "ViewSelected")) {
        $Private:Items[$Private:Name] = Get-Variable -Scope Script -Name ("DataGridQueryResultMenuItem{0}" -f $Private:Name) -ValueOnly -ErrorAction SilentlyContinue
    }
    return $Private:Items
}

function Invoke-ElementClick {
    <#
    .SYNOPSIS
        Clicks a button or a menu item from code, so its own Click handlers run.

    .PARAMETER Element
        The Button or MenuItem.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Element
    )

    $Private:Event = if ($Element -is [System.Windows.Controls.MenuItem]) { [System.Windows.Controls.MenuItem]::ClickEvent } else { [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent }
    $Element.RaiseEvent([System.Windows.RoutedEventArgs]::new($Private:Event))
}
