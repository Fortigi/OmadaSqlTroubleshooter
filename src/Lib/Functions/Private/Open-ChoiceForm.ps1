function Open-ChoiceForm {
    [CmdLetBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LeftButtonReturnValue', Justification = 'The LeftButtonReturnValue variable is used in a function called from here')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'RightButtonReturnValue', Justification = 'The RightButtonReturnValue variable is used in a function called from here')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ExtraButtonReturnValue', Justification = 'The ExtraButtonReturnValue variable is used in a function called from here')]
    param(
        $Title,
        $Message,
        $LeftButtonText = "Yes",
        $RightButtonText = "No",
        $LeftButtonReturnValue = $true,
        $RightButtonReturnValue = $false,
        # A third button, after the right one, for a question with three answers (Save / Don't save /
        # Cancel). When shown it becomes the Cancel button, so Escape picks it.
        $ExtraButtonText,
        $ExtraButtonReturnValue = $null,
        # Show a text box under the message, prefilled with -InputText. What it holds when the LEFT
        # button is clicked is left in $Script:ChoiceFormInputText; see Read-QueryNameInput.
        [switch]$ShowInput,
        [string]$InputText
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        $Script:ChoiceForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\ChoiceForm.xaml")

        $Script:ChoiceForm | Add-Member -NotePropertyName "LeftButtonReturnValue" -NotePropertyValue $LeftButtonReturnValue
        $Script:ChoiceForm | Add-Member -NotePropertyName "RightButtonReturnValue" -NotePropertyValue $RightButtonReturnValue
        $Script:ChoiceForm | Add-Member -NotePropertyName "ExtraButtonReturnValue" -NotePropertyValue $ExtraButtonReturnValue

        $Script:ChoiceForm.Definition.Title = $Title

        try {
            $Script:ChoiceForm.Definition.Icon = Get-Icon -Type Wpf
        }
        catch {
            "Failed to load application icon for choice form: {0}" -f $_.Exception.Message | Write-LogOutput -LogType WARNING
        }

        $Script:ChoiceForm.Elements.MessageText.Text = $Message

        $Script:ChoiceForm.Elements.LeftButton.Content = $LeftButtonText
        $Script:ChoiceForm.Elements.RightButton.Content = $RightButtonText

        if (![string]::IsNullOrWhiteSpace($ExtraButtonText)) {
            $Script:ChoiceForm.Elements.ExtraButton.Content = $ExtraButtonText
            $Script:ChoiceForm.Elements.ExtraButton.Visibility = [System.Windows.Visibility]::Visible
            $Script:ChoiceForm.Elements.RightButton.IsCancel = $false
            $Script:ChoiceForm.Elements.ExtraButton.IsCancel = $true
        }

        if ($ShowInput) {
            $Script:ChoiceForm.Elements.InputTextBox.Text = $InputText
            $Script:ChoiceForm.Elements.InputTextBox.Visibility = [System.Windows.Visibility]::Visible
        }

        Import-EventObjects -ClassName "ChoiceForm"

        # Own the dialog to the main window (when it is already up) so it opens in front of it and
        # takes focus, rather than appearing behind during startup.
        if ($null -ne $Script:MainForm -and $null -ne $Script:MainForm.Definition -and $Script:MainForm.Definition.IsVisible) {
            $Script:ChoiceForm.Definition.Owner = $Script:MainForm.Definition
        }

        $Script:DialogResult = $null
        $Script:ChoiceFormInputText = $null

        # See Suspend-WebViewCompletionPolling.ps1 - ShowDialog() pumps this thread's messages
        # while blocked, which could let the WebView2 completion poll timer fire reentrantly.
        Suspend-WebViewCompletionPolling
        try {
            $Script:ChoiceForm.Definition.ShowDialog() | Out-Null
        }
        finally {
            Resume-WebViewCompletionPolling
        }
        return $Script:DialogResult
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
