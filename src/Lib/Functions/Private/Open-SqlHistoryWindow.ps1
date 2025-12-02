function Open-SqlHistoryWindow {
    [CmdLetBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'Sender', Justification = 'The use of the variable is on purpose')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'Args', Justification = 'The use of the variable is on purpose')]
    param()
    try {

        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        if ($Script:RunTimeConfig.ReconnectStatus -eq 1) {
            "Skip show history" | Write-LogOutput -LogType DEBUG
            $false | Set-ConfigProperty -Property "SqlHistoryWindowFormOpen"
            return
        }

        #Log window creation
        "Opening Sql History window" | Write-LogOutput -LogType DEBUG
        $Script:SqlHistoryWindowForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\History.xaml") -ParentForm $Script:MainWindowForm.Definition
        Initialize-FormEvents -FormName "SqlHistoryWindowForm"
        [Int]$Script:SqlHistoryWindowForm.PositionManager.PositionOffSetRight = 405

        $true | Set-ConfigProperty -Property "SqlHistoryWindowFormOpen"

        $Script:SqlHistoryWindowForm.Definition.ShowInTaskbar = $false

        $Script:SqlHistoryWindowForm.Definition.Add_SizeChanged({
                $_ | Show-EventInfo -LogType VERBOSE2
                $Script:SqlHistoryWindowForm.Size = $Script:SqlHistoryWindowForm.Definition | Get-WindowSize
            })

        if ($null -ne ($Script:SqlHistoryWindowForm.Definition | Get-WindowPositionConfig)) {
            $Position = $Script:SqlHistoryWindowForm.Definition | Get-WindowPositionConfig
            "Sql history window position: {0}" -f $Position | Write-LogOutput -LogType DEBUG
            $Script:SqlHistoryWindowForm.Definition.Left = [Int]::Abs($Position.Split("x")[0])
            $Script:SqlHistoryWindowForm.Definition.Top = [Int]::Abs($Position.Split("x")[1])
        }

        # $Script:SqlHistoryWindowForm.Elements.ButtonShowDiff.Add_Click({
        #         param (
        #             $Sender,
        #             $EventArgs
        #         )

        #         try {
        #             $_ | Show-EventInfo

        #             $SelectedItem = $Script:SqlHistoryWindowForm.Elements.DataGridHistory.SelectedItem

        #             if ($null -eq $SelectedItem) {
        #                 "No history item selected" | Write-LogOutput -LogType WARNING
        #                 return
        #             }

        #             # Switch to the Diff View tab
        #             $Script:SqlHistoryWindowForm.Elements.TabControlContent.SelectedIndex = 2

        #             # Regenerate diff view to ensure it's up to date
        #             Invoke-GenerateDiffView -OldValue $SelectedItem.OldValue -NewValue $SelectedItem.NewValue

        #             "Showing diff view for: {0}" -f $SelectedItem.ChangeDate.ToString('yyyy-MM-dd HH:mm:ss') | Write-LogOutput -LogType DEBUG
        #         }
        #         catch {
        #             $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        #         }
        #     })




        #endregion
        $Script:SqlHistoryWindowForm.Definition.Show()

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }

}
