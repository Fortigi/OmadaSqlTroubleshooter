$Script:MainForm.Definition.Add_Closed({
        try {
            $_ | Show-EventInfo
            $Script:MainForm.State = "Closed"
            $Script:MainForm.Definition.Close()
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Definition.Add_Closing({
        try {
            $_ | Show-EventInfo
            $Script:MainForm.State = "Closing"
            Save-TabSessions
            Save-FormMeasurements
            if (Test-LogFormIsVisible) {
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

$Script:MainForm.Definition.Add_PreviewKeyDown({
        param(
            $EventSender,
            $EventArgs
        )
        try {
            $_ | Show-EventInfo

            $ControlPressed = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control
            $ShiftPressed = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift

            if ($EventArgs.Key -eq [System.Windows.Input.Key]::F5) {
                # When the WebView2 (Monaco editor) has focus, let Monaco handle F5 via postMessage
                # so it can include selection information for "execute selection" behaviour.
                # Only intercept here when focus is outside the WebView2.
                if ($null -ne $Script:Webview.Object -and $Script:Webview.Object.IsKeyboardFocusWithin) {
                    "F5 key at MainForm level - WebView2 has focus, deferring to Monaco" | Write-LogOutput -LogType VERBOSE
                }
                else {
                    "F5 key intercepted at MainForm level" | Write-LogOutput -LogType VERBOSE

                    $EventArgs.Handled = $true

                    "Triggering Execute Query from F5 key press (MainForm)" | Write-LogOutput -LogType VERBOSE
                    $Script:MainForm.Elements.ButtonExecuteQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                }
            }
            elseif ($EventArgs.Key -eq [System.Windows.Input.Key]::S -and $ControlPressed -and -not $ShiftPressed) {
                "Ctrl+S key intercepted at MainForm level" | Write-LogOutput -LogType VERBOSE

                $EventArgs.Handled = $true

                "Triggering Save Query from Ctrl+S key press (MainForm)" | Write-LogOutput -LogType VERBOSE
                $Script:MainForm.Elements.ButtonSaveQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            }
            elseif ($EventArgs.Key -eq [System.Windows.Input.Key]::C -and $ControlPressed -and -not $ShiftPressed) {
                # Allow Ctrl+C to pass through to DataGrid - do NOT handle it here
                "Ctrl+C detected at MainForm level - allowing to pass through to focused control" | Write-LogOutput -LogType VERBOSE
                # Do not set $EventArgs.Handled = $true for Ctrl+C
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Definition.Add_Loaded({
        try {
            $_ | Show-EventInfo

            # Flip to "Open" before anything else in this handler runs: TabControlSessions'
            # SelectionChanged guards on this state to reject the reentrant selection WPF fires
            # for TabItemAddNew as soon as the control materializes (before Loaded even starts) -
            # but Restore-TabSessions below still needs to run with State already "Open", since it
            # selects each restored TabItem synchronously through that same SelectionChanged handler.
            $Script:MainForm.State = "Open"

            if ($Script:AppGlobalConfig.LogFormOpen) {
                Open-LogForm
            }

            if ($null -ne ($Script:MainForm.Definition | Get-FormPositionConfig)) {
                $Position = $Script:MainForm.Definition | Get-FormPositionConfig
                "Main form position: {0}" -f $Position | Write-LogOutput -LogType DEBUG
                $Script:MainForm.Definition.Left = [Int]::Abs($Position.Split("x")[0])
                $Script:MainForm.Definition.Top = [Int]::Abs($Position.Split("x")[1])
            }
            if ($null -ne ($Script:MainForm.Definition | Get-FormSizeConfig)) {
                $Size = $Script:MainForm.Definition | Get-FormSizeConfig
                "Main form size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
                $Script:MainForm.Definition.Width = [Int]::Abs($Size.Split("x")[0])
                $Script:MainForm.Definition.Height = [Int]::Abs($Size.Split("x")[1])
            }

            # Per-tab WebView2 setup (runtime resolution, shared CoreWebView2Environment, Monaco
            # load, keyboard shortcuts, web-message handling) now happens once per tab inside
            # New-TabSession -> Initialize-WebViewForTab, not once globally here. Restore-TabSessions
            # creates the initial tab(s) - from persisted state, migrated legacy config, or a
            # single fresh tab on first-ever run.
            Restore-TabSessions
        }
        catch {
            "Tab session restore failed: {0}" -f $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Definition.Add_LocationChanged({
        try {
            $_ | Show-EventInfo -LogType VERBOSE2

            $ActionId = [System.Guid]::NewGuid().ToString()

            if (!$Script:MainForm.Definition.IsVisible -or $Script:MainForm.Definition.Left -lt 0 -or $Script:MainForm.Definition.Top -lt 0) {
                "MainForm is not suitable for processing. Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:MainForm.Definition.Left, $Script:MainForm.Definition.Top, $Script:MainForm.Definition.Width , $Script:MainForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
                return
            }

            "MainForm Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:MainForm.Definition.Left, $Script:MainForm.Definition.Top, $Script:MainForm.Definition.Width , $Script:MainForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
            if ((Test-LogFormIsVisible) -and -not $Script:LogForm.PositionManager.Synchronizing) {
                if ($Script:LogForm.Definition.Left -lt 0 -or $Script:LogForm.Definition.Top -lt 0) {
                    "LogForm is not suitable for processing. Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:MainForm.Definition.Left, $Script:MainForm.Definition.Top, $Script:MainForm.Definition.Width , $Script:MainForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
                    return
                }
                "LogForm Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:LogForm.Definition.Left, $Script:LogForm.Definition.Top, $Script:LogForm.Definition.Width , $Script:LogForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
                $Script:LogForm.PositionManager.Synchronizing = $true
                $Script:MainForm.Definition.Dispatcher.Invoke({
                        $Script:LogForm.Definition.Left = [Int]::Abs($Script:MainForm.Definition.Left) + [Int]::Abs($Script:LogForm.PositionManager.PositionOffSetLeft)
                        $Script:LogForm.Definition.Top = [Int]::Abs($Script:MainForm.Definition.Top) + [Int]::Abs($Script:LogForm.PositionManager.PositionOffSetTop)
                        "LogForm Position: {0}x{1}, Dimensions: {2}x{3}, PositionManagerOffSet: {4}x{5} (Id:{6})" -f $Script:LogForm.Definition.Left, $Script:LogForm.Definition.Top, $Script:LogForm.Definition.Width , $Script:LogForm.Definition.Height, $Script:LogForm.PositionManager.PositionOffSetLeft, $Script:LogForm.PositionManager.PositionOffSetTop, $ActionId | Write-LogOutput -LogType VERBOSE2
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
                $Script:MainForm.Definition.Dispatcher.Invoke({
                        $Script:SqlSchemaForm.Definition.Left = [Int]::Abs($Script:MainForm.Definition.Left) - [Int]::Abs($Script:SqlSchemaForm.PositionManager.PositionOffSetLeft)
                        $Script:SqlSchemaForm.Definition.Top = [Int]::Abs($Script:MainForm.Definition.Top) - [Int]::Abs($Script:SqlSchemaForm.PositionManager.PositionOffSetTop)
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
#$Script:MainForm.Definition.Add_SizeChanged({
#        $_ | Show-EventInfo -LogType VERBOSE2
#        if ((Test-LogFormIsVisible) -and -not $Script:LogForm.PositionManager.Synchronizing) {
#            $Script:LogForm.PositionManager.Synchronizing = $true
#            $Script:MainForm.Definition.Dispatcher.Invoke({
#                    Update-LogFormPosition
#                }, [System.Windows.Threading.DispatcherPriority]::Render)
#        }
#    })
