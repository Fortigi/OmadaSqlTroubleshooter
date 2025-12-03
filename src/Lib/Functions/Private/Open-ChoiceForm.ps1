function Open-ChoiceForm {
    [CmdLetBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LeftButtonReturnValue', Justification = 'The LeftButtonReturnValue variable is used in a function called from here')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'RightButtonReturnValue', Justification = 'The RightButtonReturnValue variable is used in a function called from here')]
    param(
        $Title,
        $Message,
        $LeftButtonText = "Yes",
        $RightButtonText = "No",
        $LeftButtonReturnValue = $true,
        $RightButtonReturnValue = $false
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        # Initialize the WPF choice window form using the same pattern as other forms
        $Script:ChoiceForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\ChoiceForm.xaml")

        # Store return values in the form object for use in events
        $Script:ChoiceForm | Add-Member -NotePropertyName "LeftButtonReturnValue" -NotePropertyValue $LeftButtonReturnValue
        $Script:ChoiceForm | Add-Member -NotePropertyName "RightButtonReturnValue" -NotePropertyValue $RightButtonReturnValue

        # Set window properties
        $Script:ChoiceForm.Definition.Title = $Title

        # Set the application icon
        try {
            $Script:ChoiceForm.Definition.Icon = Get-Icon -Type Wpf
        }
        catch {
            "Failed to load application icon for choice window: {0}" -f $_.Exception.Message | Write-LogOutput -LogType WARNING
        }

        # Set the message text
        $Script:ChoiceForm.Elements.MessageText.Text = $Message

        # Set button texts
        $Script:ChoiceForm.Elements.LeftButton.Content = $LeftButtonText
        $Script:ChoiceForm.Elements.RightButton.Content = $RightButtonText

        # Initialize events
        Initialize-FormEvents -FormName "ChoiceForm"

        # Initialize the dialog result variable
        $Script:DialogResult = $null

        # Show the dialog and return the result
        $Script:ChoiceForm.Definition.ShowDialog() | Out-Null
        return $Script:DialogResult
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
