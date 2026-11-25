function Open-SqlHistoryForm {
    [CmdLetBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'Sender', Justification = 'The use of the variable is on purpose')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'Args', Justification = 'The use of the variable is on purpose')]
    param(
        # Open the history of this query instead of the active tab's (the query manager's detail
        # view). Restore then puts the chosen version in the tab that holds the query, opening one
        # when none does (Restore-SqlQueryVersion).
        [Parameter(Mandatory = $false)]
        [string]$DoId,

        [Parameter(Mandatory = $false)]
        [string]$QueryName,

        # The window to open on top of, when that is not the main window (the query details).
        [Parameter(Mandatory = $false)]
        $Owner
    )
    try {

        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        if ($Script:RunTimeConfig.ReconnectStatus -eq 1) {
            "Skip show history" | Write-LogOutput -LogType DEBUG
            $false | Set-ConfigProperty -Property "SqlHistoryFormOpen"
            return
        }

        #Log form creation
        "Opening Sql History form" | Write-LogOutput -LogType DEBUG
        $Script:SqlHistoryTarget = $null
        if (![string]::IsNullOrWhiteSpace($DoId)) {
            $Script:SqlHistoryTarget = [PSCustomObject]@{ DoId = $DoId; QueryName = $QueryName }
        }
        $Script:SqlHistoryForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\SqlHistoryForm.xaml") -ParentForm $Script:MainForm.Definition
        if ($null -ne $Script:SqlHistoryTarget) {
            $Script:SqlHistoryForm.Definition.Title = "{0} - {1}" -f $Script:SqlHistoryForm.Definition.Title, $QueryName
        }
        if ($null -ne $Owner) {
            $Script:SqlHistoryForm.Definition.Owner = $Owner
        }
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
        # See Suspend-WebViewCompletionPolling.ps1 - ShowDialog() pumps this thread's messages
        # while blocked, which could let the WebView2 completion poll timer fire reentrantly.
        Suspend-WebViewCompletionPolling
        try {
            $Script:SqlHistoryForm.Definition.ShowDialog()
        }
        finally {
            Resume-WebViewCompletionPolling
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }

}
