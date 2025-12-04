function Open-SqlHistoryForm {
    [CmdLetBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'Sender', Justification = 'The use of the variable is on purpose')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'Args', Justification = 'The use of the variable is on purpose')]
    param()
    try {

        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        if ($Script:RunTimeConfig.ReconnectStatus -eq 1) {
            "Skip show history" | Write-LogOutput -LogType DEBUG
            $false | Set-ConfigProperty -Property "SqlHistoryFormOpen"
            return
        }

        #Log form creation
        "Opening Sql History form" | Write-LogOutput -LogType DEBUG
        $Script:SqlHistoryForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\SqlHistoryForm.xaml") -ParentForm $Script:MainForm.Definition
        Import-EventObjects -ClassName "SqlHistoryForm"
        [Int]$Script:SqlHistoryForm.PositionManager.PositionOffSetRight = 405

        $true | Set-ConfigProperty -Property "SqlHistoryFormOpen"

        $Script:SqlHistoryForm.Definition.Add_SizeChanged({
                $_ | Show-EventInfo -LogType VERBOSE2
                $Script:SqlHistoryForm.Size = $Script:SqlHistoryForm.Definition | Get-FormSize
            })

        if ($null -ne ($Script:SqlHistoryForm.Definition | Get-FormPositionConfig)) {
            $Position = $Script:SqlHistoryForm.Definition | Get-FormPositionConfig
            "Sql history form position: {0}" -f $Position | Write-LogOutput -LogType DEBUG
            $Script:SqlHistoryForm.Definition.Left = [Int]::Abs($Position.Split("x")[0])
            $Script:SqlHistoryForm.Definition.Top = [Int]::Abs($Position.Split("x")[1])
        }

        # $Script:SqlHistoryForm.Elements.ButtonShowDiff.Add_Click({
        #         param (
        #             $Sender,
        #             $EventArgs
        #         )

        #         try {
        #             $_ | Show-EventInfo

        #             $SelectedItem = $Script:SqlHistoryForm.Elements.DataGridHistory.SelectedItem

        #             if ($null -eq $SelectedItem) {
        #                 "No history item selected" | Write-LogOutput -LogType WARNING
        #                 return
        #             }

        #             # Switch to the Diff View tab
        #             $Script:SqlHistoryForm.Elements.TabControlContent.SelectedIndex = 2

        #             # Regenerate diff view to ensure it's up to date
        #             Invoke-GenerateDiffView -OldValue $SelectedItem.OldValue -NewValue $SelectedItem.NewValue

        #             "Showing diff view for: {0}" -f $SelectedItem.ChangeDate.ToString('yyyy-MM-dd HH:mm:ss') | Write-LogOutput -LogType DEBUG
        #         }
        #         catch {
        #             $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        #         }
        #     })




        #endregion
        $Script:SqlHistoryForm.Definition.ShowDialog()

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }

}
