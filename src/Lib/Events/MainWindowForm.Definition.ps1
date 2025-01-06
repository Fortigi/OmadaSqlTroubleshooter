$Script:MainWindowForm.Definition.Add_Closed({
        $_ | Show-EventInfo

        $Script:MainWindowForm.State = "Closed"
        $Script:MainWindowForm.Definition.Close()
    })

$Script:MainWindowForm.Definition.Add_Closing({
        $_ | Show-EventInfo
        $Script:MainWindowForm.State = "Closing"
        Save-WindowMeasurements
        if (Test-LogWindowOpen) {
            $Script:LogWindowForm.Definition.Close()
        }
        if (Test-SqlSchemaWindowOpen) {
            $Script:SqlSchemaWindowForm.Definition.Close()
        }
    })

$Script:MainWindowForm.Definition.Add_Loaded({
        $_ | Show-EventInfo
        try {

            if ($Script:AppConfig.LogWindowFormOpen) {
                Open-LogWindow
            }

            if ($null -ne ($Script:MainWindowForm.Definition | Get-WindowPositionConfig)) {
                $Position = $Script:MainWindowForm.Definition | Get-WindowPositionConfig
                "Main window position: {0}" -f $Position | Write-LogOutput -LogType DEBUG
                $Script:MainWindowForm.Definition.Left = [Int]::Abs($Position.Split("x")[0])
                $Script:MainWindowForm.Definition.Top = [Int]::Abs($Position.Split("x")[1])
            }
            if ($null -ne ($Script:MainWindowForm.Definition | Get-WindowSizeConfig)) {
                $Size = $Script:MainWindowForm.Definition | Get-WindowSizeConfig
                "Main window size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
                $Script:MainWindowForm.Definition.Width = [Int]::Abs($Size.Split("x")[0])
                $Script:MainWindowForm.Definition.Height = [Int]::Abs($Size.Split("x")[1])
            }

            if ($Null -eq $Script:Webview.Object) {
                [System.Windows.MessageBox]::Show("Failed to find WebView2 control.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                return
            }

            $Script:Webview.UserDataFolder = Join-Path $Env:TEMP -ChildPath "OmadaSqlTroubleshooter"
            if (-not (Test-Path -Path $Script:Webview.UserDataFolder)) {
                New-Item -Path $Script:Webview.UserDataFolder -ItemType Directory | Out-Null
            }

            $Script:Webview.EdgeWebview2RuntimePath = Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "bin\Webview2Runtime"
            if ((Test-Path -Path $Script:Webview.EdgeWebview2RuntimePath -PathType Container) -and (Test-Path -Path (Join-Path $Script:Webview.EdgeWebview2RuntimePath -ChildPath "msedgewebview2.exe") -PathType Leaf)) {
                $Script:Webview.Environment = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($Script:Webview.EdgeWebview2RuntimePath, $Script:Webview.UserDataFolder).GetAwaiter().GetResult()
            }
            else {
                $Script:Webview.Environment = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $Script:Webview.UserDataFolder).GetAwaiter().GetResult()
            }

            $Script:Webview.Object.EnsureCoreWebView2Async($Script:Webview.Environment).GetAwaiter().OnCompleted({
                    if ($Null -eq $Script:Webview.Object.CoreWebView2) {
                        $Script:MainWindowForm.Definition.Dispatcher.Invoke([System.Action] {
                                $Message = "WebView2 environment initialization failed. If this system does not have the Webview2 Runtime installed, please download the fixed version from https://developer.microsoft.com/en-us/microsoft-edge/webview2/ and extract the cab file to folder '{0}'" -f $Script:Webview.EdgeWebview2RuntimePath
                                [System.Windows.MessageBox]::Show($Message, "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                            })
                        return
                    }
                    $HtmlFile = Join-Path  $Script:RunTimeConfig.ModuleFolder -ChildPath "Monaco\index.html"
                    if ([System.IO.File]::Exists($HtmlFile)) {
                        $Script:Webview.Object.Dispatcher.Invoke([System.Action] {
                                $Script:Webview.Object.Source = New-Object System.Uri($HtmlFile)
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
                    $Script:MainWindowForm.State = "Open"
                })

        }
        catch {
            [System.Windows.MessageBox]::Show("WebView2 initialization failed: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    })

$Script:MainWindowForm.Definition.Add_LocationChanged({
        $_ | Show-EventInfo -LogType VERBOSE2

        $ActionId = [System.Guid]::NewGuid().ToString()

        if (!$Script:MainWindowForm.Definition.IsVisible -or $Script:MainWindowForm.Definition.Left -lt 0 -or $Script:MainWindowForm.Definition.Top -lt 0) {
            "MainWindowForm is not suitable for processing. Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:MainWindowForm.Definition.Left, $Script:MainWindowForm.Definition.Top, $Script:MainWindowForm.Definition.Width , $Script:MainWindowForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
            return
        }

        "MainWindow Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:MainWindowForm.Definition.Left, $Script:MainWindowForm.Definition.Top, $Script:MainWindowForm.Definition.Width , $Script:MainWindowForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
        if (Test-LogWindowOpen -and -not $Script:LogWindowForm.PositionManager.Synchronizing) {
            if ($Script:LogWindowForm.Definition.Left -lt 0 -or $Script:LogWindowForm.Definition.Top -lt 0) {
                "LogWindowForm is not suitable for processing. Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:MainWindowForm.Definition.Left, $Script:MainWindowForm.Definition.Top, $Script:MainWindowForm.Definition.Width , $Script:MainWindowForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
                return
            }
            "LogWindow Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:LogWindowForm.Definition.Left, $Script:LogWindowForm.Definition.Top, $Script:LogWindowForm.Definition.Width , $Script:LogWindowForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
            $Script:LogWindowForm.PositionManager.Synchronizing = $true
            $Script:MainWindowForm.Definition.Dispatcher.Invoke({
                    $Script:LogWindowForm.Definition.Left = [Int]::Abs($Script:MainWindowForm.Definition.Left) + [Int]::Abs($Script:LogWindowForm.PositionManager.PositionOffSetLeft)
                    $Script:LogWindowForm.Definition.Top = [Int]::Abs($Script:MainWindowForm.Definition.Top) + [Int]::Abs($Script:LogWindowForm.PositionManager.PositionOffSetTop)
                    "LogWindow Position: {0}x{1}, Dimensions: {2}x{3}, PositionManagerOffSet: {4}x{5} (Id:{6})" -f $Script:LogWindowForm.Definition.Left, $Script:LogWindowForm.Definition.Top, $Script:LogWindowForm.Definition.Width , $Script:LogWindowForm.Definition.Height, $Script:LogWindowForm.PositionManager.PositionOffSetLeft, $Script:LogWindowForm.PositionManager.PositionOffSetTop, $ActionId | Write-LogOutput -LogType VERBOSE2
                    $Script:LogWindowForm.PositionManager.Synchronizing = $false
                }, [System.Windows.Threading.DispatcherPriority]::Render)
        }
        if (Test-SqlSchemaWindowOpen -and -not $Script:SqlSchemaWindowForm.PositionManager.Synchronizing) {
            $_ | Show-EventInfo -LogType VERBOSE2
            if ($Script:SqlSchemaWindowForm.Definition.Left -lt 0 -or $Script:SqlSchemaWindowForm.Definition.Top -lt 0) {
                "SqlSchemaWindowForm is not suitable for processing. Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:SqlSchemaWindowForm.Definition.Left, $Script:SqlSchemaWindowForm.Definition.Top, $Script:SqlSchemaWindowForm.Definition.Width , $Script:SqlSchemaWindowForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
                return
            }
            "SqlSchemaWindow Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:SqlSchemaWindow.Definition.Left, $Script:SqlSchemaWindow.Definition.Top, $Script:SqlSchemaWindow.Definition.Width , $Script:SqlSchemaWindow.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
            $Script:SqlSchemaWindowForm.PositionManager.Synchronizing = $true
            $Script:MainWindowForm.Definition.Dispatcher.Invoke({
                    $Script:SqlSchemaWindowForm.Definition.Left = [Int]::Abs($Script:MainWindowForm.Definition.Left) - [Int]::Abs($Script:SqlSchemaWindowForm.PositionManager.PositionOffSetLeft)
                    $Script:SqlSchemaWindowForm.Definition.Top = [Int]::Abs($Script:MainWindowForm.Definition.Top) - [Int]::Abs($Script:SqlSchemaWindowForm.PositionManager.PositionOffSetTop)
                    "SqlSchemaWindow Position: {0}x{1}, Dimensions: {2}x{3}, PositionManagerOffSet: {4}x{5} (Id:{6})" -f $Script:SqlSchemaWindowForm.Definition.Left, $Script:SqlSchemaWindowForm.Definition.Top, $Script:SqlSchemaWindowForm.Definition.Width, $Script:SqlSchemaWindowForm.Definition.Height, $Script:SqlSchemaWindowForm.PositionManager.PositionOffSetLeft, $Script:SqlSchemaWindowForm.PositionManager.PositionOffSetTop, $ActionId | Write-LogOutput -LogType VERBOSE2
                    $Script:SqlSchemaWindowForm.PositionManager.Synchronizing = $false
                }, [System.Windows.Threading.DispatcherPriority]::Render)
        }
    })

#Find out if still needed
#$Script:MainWindowForm.Definition.Add_SizeChanged({
#        $_ | Show-EventInfo -LogType VERBOSE2
#        if (Test-LogWindowOpen -and -not $Script:LogWindowForm.PositionManager.Synchronizing) {
#            $Script:LogWindowForm.PositionManager.Synchronizing = $true
#            $Script:MainWindowForm.Definition.Dispatcher.Invoke({
#                    Update-LogWindowPosition
#                }, [System.Windows.Threading.DispatcherPriority]::Render)
#        }
#    })
