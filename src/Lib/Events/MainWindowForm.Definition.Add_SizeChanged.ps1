#Find out if still needed
#$Script:MainWindowForm.Definition.Add_SizeChanged({
#        if (Test-LogWindowOpen -and -not $Script:PositionManagerLogWindow.Synchronizing) {
#            $Script:PositionManagerLogWindow.Synchronizing = $true
#            $Script:MainWindowForm.Definition.Dispatcher.Invoke({
#                    Update-LogWindowPosition
#                }, [System.Windows.Threading.DispatcherPriority]::Render)
#        }
#    })
