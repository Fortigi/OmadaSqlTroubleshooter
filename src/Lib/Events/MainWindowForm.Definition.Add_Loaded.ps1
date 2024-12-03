$Script:MainWindowForm.Definition.Add_Loaded({
        $_ | Show-EventInfo
        try {

            if ($Script:AppConfig.LogWindowFormOpen) {
                Open-LogWindow
            }

            if ($null -ne ($Script:MainWindowForm.Definition | Get-WindowPositionConfig)) {
                $Position = $Script:MainWindowForm.Definition | Get-WindowPositionConfig
                "Main window position: {0}" -f $Position | Write-LogOutput -LogType DEBUG
                $Script:MainWindowForm.Definition.Left = [double]$Position.Split("x")[0]
                $Script:MainWindowForm.Definition.Top = [double]$Position.Split("x")[1]
            }
            if ($null -ne ($Script:MainWindowForm.Definition | Get-WindowSizeConfig)) {
                $Size = $Script:MainWindowForm.Definition | Get-WindowSizeConfig
                "Main window size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
                $Script:MainWindowForm.Definition.Width = [double]$Size.Split("x")[0]
                $Script:MainWindowForm.Definition.Height = [double]$Size.Split("x")[1]
            }

            if ($Null -eq $Script:WebView) {
                [System.Windows.MessageBox]::Show("Failed to find WebView2 control.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                return
            }

            $Script:WebviewUserDataFolder = Join-Path $Env:TEMP -ChildPath "OmadaSqlTroubleshooter"
            if (-not (Test-Path -Path $Script:WebviewUserDataFolder)) {
                New-Item -Path $Script:WebviewUserDataFolder -ItemType Directory | Out-Null
            }

            $EdgeWebview2RuntimePath = Join-Path $ScriptRootFolder -ChildPath "bin\Webview2Runtime"
            if ((Test-Path -Path $EdgeWebview2RuntimePath -PathType Container) -and (Test-Path -Path (Join-Path $EdgeWebview2RuntimePath -ChildPath "msedgewebview2.exe") -PathType Leaf)) {
                $Environment = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($EdgeWebview2RuntimePath, $Script:WebviewUserDataFolder).GetAwaiter().GetResult()
            }
            else {
                $Environment = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $Script:WebviewUserDataFolder).GetAwaiter().GetResult()
            }

            $Script:WebView.EnsureCoreWebView2Async($Environment).GetAwaiter().OnCompleted({
                    if ($Null -eq $Script:WebView.CoreWebView2) {
                        $Script:MainWindowForm.Definition.Dispatcher.Invoke([System.Action] {
                                $Message = "WebView2 environment initialization failed. If this system does not have the Webview2 Runtime installed, please download the fixed version from https://developer.microsoft.com/en-us/microsoft-edge/webview2/ and extract the cab file to folder '{0}'" -f $EdgeWebview2RuntimePath
                                [System.Windows.MessageBox]::Show($Message, "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                            })
                        return
                    }
                    $HtmlFile = Join-Path  $ScriptRootFolder -ChildPath "Monaco\index.html"
                    if ([System.IO.File]::Exists($HtmlFile)) {
                        $Script:WebView.Dispatcher.Invoke([System.Action] {
                                $Script:WebView.Source = New-Object System.Uri($HtmlFile)
                                "Webiew source set to: {0}" -f $HtmlFile | Write-LogOutput -LogType DEBUG
                            })
                    }
                    else {
                        $Script:MainWindowForm.Definition.Dispatcher.Invoke([System.Action] {
                                [System.Windows.MessageBox]::Show("Monaco HTML file not found at: $HtmlPath", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                            })
                    }
                    Test-ConnectionSettings

                    if ($Script:AppConfig.SqlSchemaWindowFormOpen) {
                        Open-SqlSchemaWindow
                    }
                })

        }
        catch {
            [System.Windows.MessageBox]::Show("WebView2 initialization failed: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    })
