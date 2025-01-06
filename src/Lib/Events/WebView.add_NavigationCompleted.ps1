$Script:Webview.Object.add_NavigationCompleted({
    $_ | Show-EventInfo
    "Set-EditorValue after loading html" | Write-LogOutput -LogType DEBUG
    Set-EditorValue

    #Not working, needs to be investigated
    #Set-EditorBackground

})
