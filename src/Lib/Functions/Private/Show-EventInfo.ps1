function Show-EventInfo {
    PARAM(
        [parameter(Mandatory = $True, Position = 0, ValueFromPipeline = $True)]
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
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
