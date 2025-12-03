$Script:Webview.Object.add_NavigationCompleted({
        try {
            $_ | Show-EventInfo
            "Set-EditorValue after loading html" | Write-LogOutput -LogType DEBUG
            Set-EditorValue

            #Not working, needs to be investigated
            #Set-EditorBackground
            $Script:RunTimeConfig.ReconnectStatus = 3
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
