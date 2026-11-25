# Menu bar (MainForm.xaml, MenuMain). Found by name on the window: $Script:MainForm.Elements is repointed
# at the active tab's controls (Set-ActiveTabContext), so it does not hold window-level ones.
# One handler per routed event on the menu itself: MenuItem.Click and MenuItem.SubmenuOpened bubble up
# to it, with the item that raised them as OriginalSource.
# Plain scriptblocks, never closures: a closure cannot see this module's private functions.

$Script:MainMenu = $Script:MainForm.Definition.FindName("MenuMain")

$Script:MainMenu.AddHandler([System.Windows.Controls.MenuItem]::SubmenuOpenedEvent, [System.Windows.RoutedEventHandler] {
        param($MenuSender, $MenuEventArgs)
        try {
            # Only a top-level menu (File, Query, ...) brings its items in line; there are no nested ones.
            if ($MenuEventArgs.OriginalSource.Parent -eq $MenuSender) {
                Update-MainMenuState -MenuItem $MenuEventArgs.OriginalSource
            }
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })

$Script:MainMenu.AddHandler([System.Windows.Controls.MenuItem]::ClickEvent, [System.Windows.RoutedEventHandler] {
        param($MenuSender, $MenuEventArgs)
        try {
            $Private:Tag = $MenuEventArgs.OriginalSource.Tag
            if ($Private:Tag -is [string] -and $Private:Tag -match ":") {
                Invoke-MainMenuAction -Tag $Private:Tag
            }
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
