$Script:MainFormForm.Definition.Add_Closed({
        try {
            $_ | Show-EventInfo
            $Script:MainFormForm.State = "Closed"
            $Script:MainFormForm.Definition.Close()
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainFormForm.Definition.Add_Closing({
        try {
            $_ | Show-EventInfo
            $Script:MainFormForm.State = "Closing"
            Save-WindowMeasurements
            if (Test-LogWindowOpen) {
                $Script:LogForm.Definition.Close()
            }
            if (Test-SqlHistoryFormOpen) {
                $Script:SqlHistoryForm.Definition.Close()
            }
            if (Test-SqlSchemaFormIsVisible) {
                $Script:SqlSchemaForm.Definition.Close()
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainFormForm.Definition.Add_PreviewKeyDown({
        param(
            $EventSender,
            $EventArgs
        )
        try {
            $_ | Show-EventInfo

            if ($EventArgs.Key -eq [System.Windows.Input.Key]::F5) {
                "F5 key intercepted at MainForm level" | Write-LogOutput -LogType VERBOSE

                $EventArgs.Handled = $true

                "Triggering Execute Query from F5 key press (MainForm)" | Write-LogOutput -LogType VERBOSE
                $Script:MainFormForm.Elements.ButtonExecuteQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            }

            elseif ($EventArgs.Key -eq [System.Windows.Input.Key]::S -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
                "Ctrl+S key intercepted at MainForm level" | Write-LogOutput -LogType VERBOSE

                $EventArgs.Handled = $true

                "Triggering Save Query from Ctrl+S key press (MainForm)" | Write-LogOutput -LogType VERBOSE
                $Script:MainFormForm.Elements.ButtonSaveQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            }

            elseif ($EventArgs.Key -eq [System.Windows.Input.Key]::C -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
                # Allow Ctrl+C to pass through to DataGrid - do NOT handle it here
                "Ctrl+C detected at MainForm level - allowing to pass through to focused control" | Write-LogOutput -LogType VERBOSE
                # Do not set $EventArgs.Handled = $true for Ctrl+C
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainFormForm.Definition.Add_Loaded({
        try {
            $_ | Show-EventInfo

            if ($Script:AppConfig.LogFormOpen) {
                Open-LogForm
            }

            if ($null -ne ($Script:MainFormForm.Definition | Get-WindowPositionConfig)) {
                $Position = $Script:MainFormForm.Definition | Get-WindowPositionConfig
                "Main window position: {0}" -f $Position | Write-LogOutput -LogType DEBUG
                $Script:MainFormForm.Definition.Left = [Int]::Abs($Position.Split("x")[0])
                $Script:MainFormForm.Definition.Top = [Int]::Abs($Position.Split("x")[1])
            }
            if ($null -ne ($Script:MainFormForm.Definition | Get-WindowSizeConfig)) {
                $Size = $Script:MainFormForm.Definition | Get-WindowSizeConfig
                "Main window size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
                $Script:MainFormForm.Definition.Width = [Int]::Abs($Size.Split("x")[0])
                $Script:MainFormForm.Definition.Height = [Int]::Abs($Size.Split("x")[1])
            }

            if ($null -eq $Script:Webview.Object) {
                "Failed to find WebView2 control." | Write-LogOutput -LogType ERROR
                # [System.Windows.MessageBox]::Show("Failed to find WebView2 control.", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }

            $Script:Webview.UserDataFolder = Join-Path $Env:TEMP -ChildPath "OmadaSqlTroubleshooter"
            if (-not (Test-Path -Path $Script:Webview.UserDataFolder)) {
                New-Item -Path $Script:Webview.UserDataFolder -ItemType Directory | Out-Null
            }

            $Script:Webview.EdgeWebview2RuntimePath = Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "bin\Webview2Runtime"
            if (!(Test-Path ($Script:WebView.EdgeWebview2RuntimePath ) -PathType Container)) {
                $Script:Webview.EdgeWebview2RuntimePath = Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)) -ChildPath "OmadaSqlTroubleShooter\bin\Webview2Runtime"
            }
            if ((Test-Path -Path $Script:Webview.EdgeWebview2RuntimePath -PathType Container) -and (Test-Path -Path (Join-Path $Script:Webview.EdgeWebview2RuntimePath -ChildPath "msedgewebview2.exe") -PathType Leaf)) {
                $Script:Webview.Environment = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($Script:Webview.EdgeWebview2RuntimePath, $Script:Webview.UserDataFolder).GetAwaiter().GetResult()
            }
            else {
                $Script:Webview.Environment = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $Script:Webview.UserDataFolder).GetAwaiter().GetResult()
            }

            if (-not (Test-Path $Script:WebView2UserProfilePath -PathType Container)) { New-Item -ItemType Directory -Force -Path $Script:WebView2UserProfilePath | Out-Null }

            $Script:Webview.Object.EnsureCoreWebView2Async($Script:Webview.Environment).GetAwaiter().OnCompleted({
                "EnsureCoreWebView2Async OnCompleted script" | Write-LogOutput -LogType DEBUG
                    if ($null -eq $Script:Webview.Object.CoreWebView2) {
                        $Script:MainFormForm.Definition.Dispatcher.Invoke([System.Action] {
                                $Message = "WebView2 environment initialization failed. If this system does not have the Webview2 Runtime installed, please download the fixed version from https://developer.microsoft.com/en-us/microsoft-edge/webview2/ and extract the cab file to folder '{0}'" -f $Script:Webview.EdgeWebview2RuntimePath
                                $Message | Write-LogOutput -LogType ERROR
                                #[System.Windows.MessageBox]::Show($Message, "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
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
                        $Script:MainFormForm.Definition.Dispatcher.Invoke([System.Action] {
                                #[System.Windows.MessageBox]::Show("Monaco HTML file not found at: $HtmlPath", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
                                "Monaco HTML file not found at: {0}" -f $HtmlPath | Write-LogOutput -LogType ERROR
                            })
                    }
                    Test-ConnectionButton

                    if ($Script:AppConfig.SqlSchemaFormOpen) {
                        Open-SqlSchemaForm
                    }
                    Update-QueryList

                    $Script:Webview.Object.add_PreviewKeyDown({
                            param(
                                $EventSender,
                                $EventArgs
                            )
                            try {
                                $_ | Show-EventInfo

                                if ($EventArgs.Key -eq [System.Windows.Input.Key]::F5) {
                                    "F5 key intercepted in WebView2 (PreviewKeyDown)" | Write-LogOutput -LogType DEBUG

                                    $EventArgs.Handled = $true

                                    $Script:MainFormForm.Definition.Dispatcher.Invoke([System.Action] {
                                            "Triggering Execute Query from F5 key press" | Write-LogOutput -LogType DEBUG
                                            $Script:MainFormForm.Elements.ButtonExecuteQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                                        })
                                }
                                elseif ($EventArgs.Key -eq [System.Windows.Input.Key]::S -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
                                    "Ctrl+S key intercepted in WebView2 (PreviewKeyDown)" | Write-LogOutput -LogType DEBUG

                                    $EventArgs.Handled = $true

                                    $Script:MainFormForm.Definition.Dispatcher.Invoke([System.Action] {
                                            "Triggering Save Query from Ctrl+S key press" | Write-LogOutput -LogType DEBUG
                                            $Script:MainFormForm.Elements.ButtonSaveQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                                        })
                                }
                            }
                            catch {
                                $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                            }
                        })

                    $Script:Webview.Object.CoreWebView2.add_WebMessageReceived({
                            param(
                                $EventSender,
                                $EventArgs
                            )
                            try {
                                $_ | Show-EventInfo
                                "CoreWebView2.add_WebMessageReceived" | Write-LogOutput -LogType DEBUG

                                $message = $EventArgs.TryGetWebMessageAsString()
                                "WebView2 message received: {0}" -f $message | Write-LogOutput -LogType DEBUG

                                if ($message) {
                                    $messageObj = $message | ConvertFrom-Json -ErrorAction SilentlyContinue
                                    if ($messageObj -and $messageObj.type -eq 'executeQuery') {
                                        "Execute Query requested from Monaco Editor via {0}" -f $messageObj.key | Write-LogOutput -LogType DEBUG

                                        $Script:MainFormForm.Definition.Dispatcher.Invoke([System.Action] {
                                                $Script:MainFormForm.Elements.ButtonExecuteQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                                            })
                                    }
                                    elseif ($messageObj -and $messageObj.type -eq 'saveQuery') {
                                        "Save Query requested from Monaco Editor via {0}" -f $messageObj.key | Write-LogOutput -LogType DEBUG

                                        $Script:MainFormForm.Definition.Dispatcher.Invoke([System.Action] {
                                                $Script:MainFormForm.Elements.ButtonSaveQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                                            })
                                    }
                                }
                            }
                            catch {
                                $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                            }
                        })

                    $Script:MainFormForm.State = "Open"
                })
        }
        catch {
            "WebView2 initialization failed: {0}" -f $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainFormForm.Definition.Add_LocationChanged({
        try {
            $_ | Show-EventInfo -LogType VERBOSE2

            $ActionId = [System.Guid]::NewGuid().ToString()

            if (!$Script:MainFormForm.Definition.IsVisible -or $Script:MainFormForm.Definition.Left -lt 0 -or $Script:MainFormForm.Definition.Top -lt 0) {
                "MainFormForm is not suitable for processing. Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:MainFormForm.Definition.Left, $Script:MainFormForm.Definition.Top, $Script:MainFormForm.Definition.Width , $Script:MainFormForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
                return
            }

            "MainForm Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:MainFormForm.Definition.Left, $Script:MainFormForm.Definition.Top, $Script:MainFormForm.Definition.Width , $Script:MainFormForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
            if ((Test-LogWindowOpen) -and -not $Script:LogForm.PositionManager.Synchronizing) {
                if ($Script:LogForm.Definition.Left -lt 0 -or $Script:LogForm.Definition.Top -lt 0) {
                    "LogForm is not suitable for processing. Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:MainFormForm.Definition.Left, $Script:MainFormForm.Definition.Top, $Script:MainFormForm.Definition.Width , $Script:MainFormForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
                    return
                }
                "LogWindow Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:LogForm.Definition.Left, $Script:LogForm.Definition.Top, $Script:LogForm.Definition.Width , $Script:LogForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
                $Script:LogForm.PositionManager.Synchronizing = $true
                $Script:MainFormForm.Definition.Dispatcher.Invoke({
                        $Script:LogForm.Definition.Left = [Int]::Abs($Script:MainFormForm.Definition.Left) + [Int]::Abs($Script:LogForm.PositionManager.PositionOffSetLeft)
                        $Script:LogForm.Definition.Top = [Int]::Abs($Script:MainFormForm.Definition.Top) + [Int]::Abs($Script:LogForm.PositionManager.PositionOffSetTop)
                        "LogWindow Position: {0}x{1}, Dimensions: {2}x{3}, PositionManagerOffSet: {4}x{5} (Id:{6})" -f $Script:LogForm.Definition.Left, $Script:LogForm.Definition.Top, $Script:LogForm.Definition.Width , $Script:LogForm.Definition.Height, $Script:LogForm.PositionManager.PositionOffSetLeft, $Script:LogForm.PositionManager.PositionOffSetTop, $ActionId | Write-LogOutput -LogType VERBOSE2
                        $Script:LogForm.PositionManager.Synchronizing = $false
                    }, [System.Windows.Threading.DispatcherPriority]::Render)
            }
            if ((Test-SqlSchemaFormIsVisible) -and -not $Script:SqlSchemaForm.PositionManager.Synchronizing) {
                $_ | Show-EventInfo -LogType VERBOSE2
                if ($Script:SqlSchemaForm.Definition.Left -lt 0 -or $Script:SqlSchemaForm.Definition.Top -lt 0) {
                    "SqlSchemaForm is not suitable for processing. Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:SqlSchemaForm.Definition.Left, $Script:SqlSchemaForm.Definition.Top, $Script:SqlSchemaForm.Definition.Width , $Script:SqlSchemaForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
                    return
                }
                "SqlSchemaForm Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:SqlSchemaForm.Definition.Left, $Script:SqlSchemaForm.Definition.Top, $Script:SqlSchemaForm.Definition.Width , $Script:SqlSchemaForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
                $Script:SqlSchemaForm.PositionManager.Synchronizing = $true
                $Script:MainFormForm.Definition.Dispatcher.Invoke({
                        $Script:SqlSchemaForm.Definition.Left = [Int]::Abs($Script:MainFormForm.Definition.Left) - [Int]::Abs($Script:SqlSchemaForm.PositionManager.PositionOffSetLeft)
                        $Script:SqlSchemaForm.Definition.Top = [Int]::Abs($Script:MainFormForm.Definition.Top) - [Int]::Abs($Script:SqlSchemaForm.PositionManager.PositionOffSetTop)
                        "SqlSchemaForm Position: {0}x{1}, Dimensions: {2}x{3}, PositionManagerOffSet: {4}x{5} (Id:{6})" -f $Script:SqlSchemaForm.Definition.Left, $Script:SqlSchemaForm.Definition.Top, $Script:SqlSchemaForm.Definition.Width, $Script:SqlSchemaForm.Definition.Height, $Script:SqlSchemaForm.PositionManager.PositionOffSetLeft, $Script:SqlSchemaForm.PositionManager.PositionOffSetTop, $ActionId | Write-LogOutput -LogType VERBOSE2
                        $Script:SqlSchemaForm.PositionManager.Synchronizing = $false
                    }, [System.Windows.Threading.DispatcherPriority]::Render)
            }
        }
        catch {
            #[System.Windows.MessageBox]::Show("WebView2 initialization failed: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
            "WebView2 initialization failed: {0}" -f $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

#Find out if still needed
#$Script:MainFormForm.Definition.Add_SizeChanged({
#        $_ | Show-EventInfo -LogType VERBOSE2
#        if ((Test-LogWindowOpen) -and -not $Script:LogForm.PositionManager.Synchronizing) {
#            $Script:LogForm.PositionManager.Synchronizing = $true
#            $Script:MainFormForm.Definition.Dispatcher.Invoke({
#                    Update-LogWindowPosition
#                }, [System.Windows.Threading.DispatcherPriority]::Render)
#        }
#    })
