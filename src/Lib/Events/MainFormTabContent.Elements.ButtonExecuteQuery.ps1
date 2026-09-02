$Script:MainForm.Elements.ButtonExecuteQuery.Add_Click({
        try {
            $_ | Show-EventInfo

            $Script:RunTimeData.StopWatch = [System.Diagnostics.Stopwatch]::StartNew()

            $Script:PopupWindowExecuteQuery = Show-PopupWindow -Message "Executing Query..."

            $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $false
            $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $false
            $Script:MainForm.Elements.ButtonShowOutput.IsEnabled = $false
            $Script:MainForm.Elements.ButtonSaveOutputFile.IsEnabled = $false

            # Let the "Executing Query..." popup actually paint before this handler goes on to block.
            # This used to be Start-Sleep -Milliseconds 100, which cannot work: Start-Sleep parks the
            # dispatcher thread without pumping it, so the render pass the popup is waiting for never
            # runs - the window simply froze 100 ms longer with nothing new on screen.
            # (Show-PopupWindow uses .Show(), not .ShowDialog(), so nothing else pumps for it either.)
            # Invoking an empty action at Background priority drains everything of higher priority
            # first - Render included - which is exactly the pass that draws the popup. Same primitive
            # the E2E harness uses as Invoke-E2EFlushDispatcher.
            $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)

            if (!(Test-ConnectionRequirements) -or [string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentSqlQuery.DoId)) {
                "Omada Url not set or Query not selected, cannot retrieve data!" | Write-LogOutput -LogType WARNING
                if ($null -ne $Script:PopupWindowExecuteQuery) {
                    $Script:PopupWindowExecuteQuery.Close()
                }
                Restore-MainFormFocus
            }
            else {
                "Execute" | Write-LogOutput
                Invoke-ExecuteQuery
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

#    $Script:MainForm.Elements.ButtonExecuteQueryText.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonExecuteQuery"
#    })

#$Script:MainForm.Elements.ButtonExecuteQueryImage.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonExecuteQuery"
#    })
