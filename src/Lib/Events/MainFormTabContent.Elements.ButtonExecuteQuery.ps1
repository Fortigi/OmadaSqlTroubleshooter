$Script:MainForm.Elements.ButtonExecuteQuery.Add_Click({
        try {
            $_ | Show-EventInfo

            # While a query is in flight this button reads "Cancel" (Set-ExecuteQueryButtonState), so
            # a click here is a request to stop waiting rather than to execute again. Checked first,
            # before any of the start-an-execute work below - starting a stopwatch and showing a
            # popup on the way to cancelling would be exactly backwards.
            if ($null -ne (Get-ActiveExecuteQueryRequest)) {
                "Cancel requested for the running query." | Write-LogOutput
                Stop-ExecuteQueryRequest
                return
            }

            $Script:RunTimeData.StopWatch = [System.Diagnostics.Stopwatch]::StartNew()

            Show-ExecuteQueryPopup

            $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $false
            $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $false
            $Script:MainForm.Elements.ButtonShowOutput.IsEnabled = $false
            $Script:MainForm.Elements.ButtonSaveOutputFile.IsEnabled = $false

            # Let the "Executing Query..." popup actually paint before this handler continues.
            # This used to be Start-Sleep -Milliseconds 100, which cannot work: Start-Sleep parks the
            # dispatcher thread without pumping it, so the render pass the popup is waiting for never
            # runs - the window simply froze 100 ms longer with nothing new on screen.
            # (Show-PopupWindow uses .Show(), not .ShowDialog(), so nothing else pumps for it either.)
            # Invoking an empty action at Background priority drains everything of higher priority
            # first - Render included - which is exactly the pass that draws the popup.
            #
            # Suspended around the pump, and this is not optional. Pumping the dispatcher is exactly
            # what lets the WebViewCompletionPollTimer fire, and a completion drained here runs
            # Set-ActiveTabContext - repointing $Script:MainForm.Elements, $Script:RunTimeData and
            # $Script:AppConfig - in the middle of this handler, after it has already disabled the
            # buttons on the tab it started with. Observed: the buttons stayed disabled on the OLD
            # element bag while the execute ran against a different one. The suspend keeps the render
            # pass (which is all this needs) and denies the timer, which is the same reasoning
            # Suspend-WebViewCompletionPolling was written for.
            Suspend-WebViewCompletionPolling
            try {
                $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
            }
            finally {
                Resume-WebViewCompletionPolling
            }

            if (!(Test-ConnectionRequirements) -or [string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentSqlQuery.DoId)) {
                "Omada Url not set or Query not selected, cannot retrieve data!" | Write-LogOutput -LogType WARNING
                Close-ExecuteQueryPopup
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
