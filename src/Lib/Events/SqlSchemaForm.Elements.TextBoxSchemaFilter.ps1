# Debounce the filter: a large database schema puts thousands of TreeViewItems in the tree, and
# re-evaluating all of them on every keystroke makes typing feel sticky. The timer is created here,
# at the top level of an event file, and its Tick handler is a plain scriptblock - see the comment
# in MainForm.Definition.ps1: a .GetNewClosure() block runs in a detached dynamic module that cannot
# resolve this module's private functions.
$Script:SqlSchemaFilterTimer = New-Object System.Windows.Threading.DispatcherTimer
$Script:SqlSchemaFilterTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$Script:SqlSchemaFilterTimer.Add_Tick({
        try {
            $Script:SqlSchemaFilterTimer.Stop()
            Update-SqlSchemaTreeFilter
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:SqlSchemaForm.Elements.TextBoxSchemaFilter.Add_TextChanged({

        param (
            $EventSender,
            $EventArgs
        )

        try {
            $_ | Show-EventInfo -LogType VERBOSE2

            # Restart the countdown on every keystroke so the filter is applied once the user pauses.
            $Script:SqlSchemaFilterTimer.Stop()
            $Script:SqlSchemaFilterTimer.Start()
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:SqlSchemaForm.Elements.TextBoxSchemaFilter.Add_PreviewKeyDown({

        param (
            $EventSender,
            $EventArgs
        )

        try {
            $_ | Show-EventInfo -LogType VERBOSE2

            if ($EventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
                "Escape key intercepted at schema filter level - clearing the filter" | Write-LogOutput -LogType VERBOSE

                $EventArgs.Handled = $true
                # Clearing the text raises TextChanged, which restarts the debounce timer and
                # restores the full tree.
                $Script:SqlSchemaForm.Elements.TextBoxSchemaFilter.Clear()
            }
            elseif ($EventArgs.Key -in ([System.Windows.Input.Key]::Enter, [System.Windows.Input.Key]::Return)) {
                "Enter/Return key intercepted at schema filter level - applying the filter" | Write-LogOutput -LogType VERBOSE

                $EventArgs.Handled = $true
                $Script:SqlSchemaFilterTimer.Stop()
                Update-SqlSchemaTreeFilter
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
