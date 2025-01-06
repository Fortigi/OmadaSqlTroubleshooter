function Invoke-OnTreeViewItemShiftClick {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'Sender', Justification = 'The use of the variable is on purpose')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'Args', Justification = 'The use of the variable is on purpose')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Args', Justification = 'The variable is declared because the call contains the parameter')]
    PARAM (
        $Sender,
        $Args
    )

    try {
        "Left shift {0}, Right shift {1}" -f [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::LeftShift), [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::RightShift) | Write-LogOutput -LogType VERBOSE

        if ([System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::LeftShift) -or
            [System.Windows.Input.Keyboard]::IsKeyDown([System.Windows.Input.Key]::RightShift)) {

            if ($Sender.SelectedItem.IsSelected) {

                $ItemValue = $Sender.SelectedValue.Header.ToString()
                [System.Windows.Clipboard]::SetText($ItemValue)
                "Copied to clipboard: {0}" -f $ItemValue | Write-LogOutput -LogType DEBUG
                if ($null -eq $Script:PreviousLevel) {
                    $Script:PreviousLevel = -1
                }

                switch (Get-TreeviewItemLevel -TreeViewItem $Sender.SelectedItem) {
                    "0" {
                        "Tree view level: {0}, previous: {1}" -f $_, $Script:PreviousLevel | Write-LogOutput -LogType VERBOSE
                        $ItemValue = "{0}." -f $ItemValue.Trim()

                        $Script:PreviousLevel = $_

                    }
                    "1" {
                        "Tree view level: {0}, previous: {1}" -f $_, $Script:PreviousLevel | Write-LogOutput -LogType VERBOSE
                        if ($Script:PreviousLevel -eq 0) {
                            $ItemValue = "{0}" -f $ItemValue.Trim()
                        }
                        else {
                            $ItemValue = " {0}" -f $ItemValue.Trim()
                        }
                        $Script:PreviousLevel = $_
                    }
                    "2" {
                        "Tree view level: {0}, previous: {1}" -f $_, $Script:PreviousLevel | Write-LogOutput -LogType VERBOSE
                        if ($Script:PreviousLevel -eq 1) {
                            $ItemValue = ".{0}" -f ($ItemValue.Trim().Split(" ")[0])
                        }
                        else {
                            $ItemValue = " {0}," -f ($ItemValue.Trim().Split(" ")[0])
                        }
                        $Script:PreviousLevel = $_
                    }
                    default {
                        "Tree view level: {0}" -f $_ | Write-LogOutput -LogType VERBOSE
                    }
                }

                $ScriptToExecute = "try {{
    editor.focus();
    const position = editor.getPosition();
    const range = new monaco.Range(position.lineNumber, position.column, position.lineNumber, position.column);
    console.log('Range:', range);
    editor.executeEdits('', [{{ range, text: '{0}', forceMoveMarkers: true }}]);
    console.log('Edit executed successfully');
}} catch (error) {{
    console.error('Edit failed:', error);
}}" -f $ItemValue

                $Script:SenderTest = $Sender
                "Execute script in in Monaco Editor:`r`n{0}" -f $ScriptToExecute | Write-LogOutput -LogType DEBUG
                $OnCompletedScriptBlock = {
                    try {
                        if (!$Script:Task.Status -eq "RanToCompletion") {
                            "Monaco Editor Task failed: {0}" -f $Script:Task.Status | Write-LogOutput -LogType ERROR
                        }
                        else {
                            "Monaco Editor Task completed successfully: {0}" -f $Script:Task.Result | Write-LogOutput -LogType DEBUG
                        }
                    }
                    catch {
                        $Script:Task.Exception.Message | Write-LogOutput -LogType ERROR
                    }
                    if ($null -ne $Script:SenderTest.SelectedItem) {
                        $Script:SenderTest.SelectedItem.IsSelected = $false
                        $Script:MainWindowForm.Definition.Focus()
                        $Script:Webview.Object.Focus()
                    }
                }

                "Set value in Monaco editor." | Write-LogOutput -LogType DEBUG
                Invoke-ExecuteScriptWithResultAsync -ScriptToExecute $ScriptToExecute -OnCompletedScriptBlock $OnCompletedScriptBlock
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
