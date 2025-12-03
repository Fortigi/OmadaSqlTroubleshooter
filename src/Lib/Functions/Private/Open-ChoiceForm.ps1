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

        $Script:ChoiceForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\ChoiceForm.xaml")

        $Script:ChoiceForm | Add-Member -NotePropertyName "LeftButtonReturnValue" -NotePropertyValue $LeftButtonReturnValue
        $Script:ChoiceForm | Add-Member -NotePropertyName "RightButtonReturnValue" -NotePropertyValue $RightButtonReturnValue

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

        Initialize-FormEvents -FormName "ChoiceForm"

        $Script:DialogResult = $null

        $Script:ChoiceForm.Definition.ShowDialog() | Out-Null
        return $Script:DialogResult
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
