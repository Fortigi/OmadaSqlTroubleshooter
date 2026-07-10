function New-TabContextMenu {
    <#
    .SYNOPSIS
    Builds the right-click context menu for a tab: Save, Duplicate, Close, Close Others, Close All.
    Styled to match the DataGrid result context menu via the TabContextMenuTemplate / TabFlatMenuItem
    resources in MainForm.xaml. Each item carries the tab id on its Tag so its click handler can stay
    a plain scriptblock (no GetNewClosure - which cannot resolve this module's private functions),
    recovering the tab from its sender's Tag.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession
    )
    try {
        $BrushConverter = New-Object System.Windows.Media.BrushConverter
        $TextBrush = $BrushConverter.ConvertFromString("#1F1F1F")
        $IconBrush = $BrushConverter.ConvertFromString("#4B5563")

        $Menu = New-Object System.Windows.Controls.ContextMenu
        $Menu.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
        $Menu.FontSize = 13
        $Menu.Foreground = $TextBrush
        $Menu.Tag = $TabSession.Id
        $Template = $Script:MainForm.Definition.TryFindResource("TabContextMenuTemplate")
        if ($null -ne $Template) {
            $Menu.Template = $Template
        }
        $FlatTemplate = $Script:MainForm.Definition.TryFindResource("TabFlatMenuItem")
        $SeparatorTemplate = $Script:MainForm.Definition.TryFindResource("TabMenuSeparatorTemplate")

        $BuildItem = {
            param($Header, $Gesture, $Glyph, $ClickHandler)
            $Item = New-Object System.Windows.Controls.MenuItem
            $Item.Header = $Header
            if (![string]::IsNullOrEmpty($Gesture)) {
                $Item.InputGestureText = $Gesture
            }
            if ($null -ne $FlatTemplate) {
                $Item.Template = $FlatTemplate
            }
            $Item.Tag = $TabSession.Id
            if (![string]::IsNullOrEmpty($Glyph)) {
                $Icon = New-Object System.Windows.Controls.TextBlock
                $Icon.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets")
                $Icon.FontSize = 14
                $Icon.Text = $Glyph
                $Icon.Foreground = $IconBrush
                $Item.Icon = $Icon
            }
            $Item.Add_Click($ClickHandler)
            return $Item
        }

        $SaveItem = & $BuildItem "Save" "Ctrl+S" ([char]0xE74E) {
                param($ClickSender)
                try {
                    $_ | Show-EventInfo
                    $Tab = $Script:Tabs | Where-Object { $_.Id -eq $ClickSender.Tag } | Select-Object -First 1
                    if ($null -ne $Tab) {
                        Set-ActiveTabContext -TabSession $Tab
                        $Script:MainForm.Elements.ButtonSaveQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                    }
                }
                catch {
                    $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            }

        $DuplicateItem = & $BuildItem "Duplicate Tab" "Ctrl+Shift+K" ([char]0xE8C8) {
                param($ClickSender)
                try {
                    $_ | Show-EventInfo
                    Invoke-DuplicateTab -TabId $ClickSender.Tag
                }
                catch {
                    $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            }

        $CloseItem = & $BuildItem "Close" "Ctrl+W" ([char]0xE8BB) {
                param($ClickSender)
                try {
                    $_ | Show-EventInfo
                    Close-TabSession -TabId $ClickSender.Tag
                }
                catch {
                    $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            }

        $CloseOthersItem = & $BuildItem "Close All But This" $null ([char]0xE89F) {
                param($ClickSender)
                try {
                    $_ | Show-EventInfo
                    Close-OtherTabSessions -KeepTabId $ClickSender.Tag
                }
                catch {
                    $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            }

        $CloseAllItem = & $BuildItem "Close All" $null ([char]0xE8BB) {
                param($ClickSender)
                try {
                    $_ | Show-EventInfo
                    Close-AllTabSessions
                }
                catch {
                    $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            }

        $Separator = New-Object System.Windows.Controls.Separator
        if ($null -ne $SeparatorTemplate) {
            $Separator.Template = $SeparatorTemplate
        }

        [void]$Menu.Items.Add($SaveItem)
        [void]$Menu.Items.Add($DuplicateItem)
        [void]$Menu.Items.Add($Separator)
        [void]$Menu.Items.Add($CloseItem)
        [void]$Menu.Items.Add($CloseOthersItem)
        [void]$Menu.Items.Add($CloseAllItem)

        # Keep the Save item's enabled state in sync with the tab's Save button each time the menu
        # opens (rule: Save is available only when the tab's Save button is enabled).
        $Menu.Add_Opened({
                param($MenuSender)
                try {
                    $Tab = $Script:Tabs | Where-Object { $_.Id -eq $MenuSender.Tag } | Select-Object -First 1
                    if ($null -ne $Tab) {
                        $Save = $MenuSender.Items | Where-Object { $_ -is [System.Windows.Controls.MenuItem] -and $_.Header -eq "Save" } | Select-Object -First 1
                        if ($null -ne $Save) {
                            $Save.IsEnabled = [bool]$Tab.Elements.ButtonSaveQuery.IsEnabled
                        }
                    }
                }
                catch {
                    $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            })

        return $Menu
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        return $null
    }
}
