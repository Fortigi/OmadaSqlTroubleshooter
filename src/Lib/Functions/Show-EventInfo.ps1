function Show-EventInfo {

    PARAM(
        [parameter(Mandatory = $True, Position = 0, ValueFromPipeline = $True)]
        $Item
    )
    try {
        if ($Item -is [Microsoft.Web.WebView2.Core.CoreWebView2NavigationCompletedEventArgs]) {
            "Webview success: '{0}'" -f $Item.IsSuccess | Write-LogOutput -LogType DEBUG
        }
        elseif ($Item -is [System.Windows.Window]) {
            "Form: '{0}', Event: '{1}', Event Type: '{2}'" -f $Item.Source.Title, $Item.RoutedEvent.Name, $Item.RoutedEvent.OwnerType.FullName | Write-LogOutput -LogType DEBUG
        }
        elseif ($Item -is [System.Windows.Controls.SelectionChangedEventArgs]) {
            "Control: '{0}', Event: '{1}', Event Type: '{2}', Added values: {3}, Removed values: {4}" -f $Item.Source.Name, $Item.RoutedEvent.Name, $Item.RoutedEvent.OwnerType.FullName, ($Item.AddedItems | Measure-Object).Count, ($Item.RemovedItems | Measure-Object).Count | Write-LogOutput -LogType DEBUG
        }
        elseif ($Item -is [System.Windows.RoutedEventArgs]) {
            "Event: '{0}', Event Type: '{1}" -f $Item.RoutedEvent.Name, $Item.RoutedEvent.OwnerType.FullName | Write-LogOutput -LogType DEBUG
        }
        elseif ($Item -is [System.EventArgs]) {
            "Event: '{0}'" -f $Item.RoutedEvent.Name | Write-LogOutput -LogType DEBUG
        }
        else {
            "Control: {0}, Event: '{1}', Event Type: '{2}'" -f $Item.Source.Name, $Item.RoutedEvent.Name, $Item.RoutedEvent.OwnerType.FullName | Write-LogOutput -LogType DEBUG
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
