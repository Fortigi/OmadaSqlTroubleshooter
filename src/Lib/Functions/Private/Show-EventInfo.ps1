function Show-EventInfo {
    param(
        [parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        $Item,
        [validateSet("DEBUG", "VERBOSE", "VERBOSE2")]
        $LogType = "DEBUG"
    )
    try {
        $CallStack = Get-PSCallStack
        if ($Item -is [Microsoft.Web.WebView2.Core.CoreWebView2NavigationCompletedEventArgs]) {
            "Webview success: '{0}' Source: '{1}'" -f $Item.IsSuccess, $CallStack[1].Location | Write-LogOutput -LogType $LogType
        }
        elseif ($Item -is [System.Windows.Window]) {
            "Form: '{0}', Event: '{1}', Event Type: '{2}', Source: '{3}'" -f $Item.Source.Title, $Item.RoutedEvent.Name, $Item.RoutedEvent.OwnerType.FullName, $CallStack[1].Location | Write-LogOutput -LogType $LogType
        }
        elseif ($Item -is [System.Windows.Controls.SelectionChangedEventArgs]) {
            "Control: '{0}', Event: '{1}', Event Type: '{2}', Added values: {3}, Removed values: {4}, Source: '{5}'" -f $Item.Source.Name, $Item.RoutedEvent.Name, $Item.RoutedEvent.OwnerType.FullName, ($Item.AddedItems | Measure-Object).Count, ($Item.RemovedItems | Measure-Object).Count, $CallStack[1].Location | Write-LogOutput -LogType $LogType
        }
        elseif ($Item -is [System.Windows.SizeChangedEventArgs]) {
            "Control: '{0}', Event: '{1}', Event Type: '{2}', PreviousSize: {3}, NewSize: {4}, Source: {5}" -f $Item.Source.Name, $Item.RoutedEvent.Name, $Item.RoutedEvent.OwnerType.FullName, $Item.PreviousSize, $Item.NewSize, $CallStack[1].Location | Write-LogOutput -LogType $LogType
        }
        elseif ($Item -is [System.Windows.Input.KeyEventArgs]) {
            # KeyEventArgs derives from RoutedEventArgs, so this branch must precede the generic
            # RoutedEventArgs one below. A held key auto-repeats PreviewKeyDown/KeyDown many times a
            # second, which floods the log with identical lines - log only the initial press and the
            # release (KeyUp is never a repeat), skipping every auto-repeat in between.
            if ($Item.IsRepeat) {
                return
            }
            $PressedKey = if ($Item.Key -eq [System.Windows.Input.Key]::System) { $Item.SystemKey } else { $Item.Key }

            # Security: only record keys that form a shortcut. Logging every keystroke would let a
            # secret typed into a field (e.g. a password) be reconstructed from the log.
            if (-not (Test-ShortcutKey -KeyName ([string]$PressedKey) -ModifierNames ([System.Windows.Input.Keyboard]::Modifiers.ToString()))) {
                return
            }

            $KeyAction = if ($null -ne $Item.RoutedEvent -and $Item.RoutedEvent.Name -like "*Up") { "released" } else { "pressed" }
            "Key {0}: '{1}', Modifiers: '{2}', Event: '{3}', Source: '{4}'" -f $KeyAction, $PressedKey, [System.Windows.Input.Keyboard]::Modifiers, $Item.RoutedEvent.Name, $CallStack[1].Location | Write-LogOutput -LogType $LogType
        }
        elseif ($Item -is [System.Windows.RoutedEventArgs]) {
            "Event: '{0}', Event Type: '{1}, Source: '{2}'" -f $Item.RoutedEvent.Name, $Item.RoutedEvent.OwnerType.FullName, $CallStack[1].Location | Write-LogOutput -LogType $LogType
        }
        elseif ($Item -is [System.EventArgs]) {
            if ([string]::IsNullOrWhiteSpace($Item.RoutedEvent.Name)) {
                "Event: '{0}', Source: '{1}'" -f $Item, $CallStack[1].Location | Write-LogOutput -LogType $LogType
            }
            else {
                "Event: '{0}', Source: '{1}'" -f $Item.RoutedEvent.Name, $CallStack[1].Location | Write-LogOutput -LogType $LogType
            }
        }
        else {
            "Control: {0}, Event: '{1}', Event Type: '{2}', Source: '{3}'" -f $Item.Source.Name, $Item.RoutedEvent.Name, $Item.RoutedEvent.OwnerType.FullName, $CallStack[1].Location | Write-LogOutput -LogType $LogType
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
