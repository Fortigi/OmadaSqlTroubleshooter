function Save-AdHocQuery {
    <#
    .SYNOPSIS
        Saves the active tab's ad-hoc query as a new query object, from the Save button or Ctrl+S.

    .DESCRIPTION
        Save on an ad-hoc query means "create it": there is no object to update. The name is asked
        for (Request-NewSqlQueryName) and put in the Display name box, and the save itself is the
        existing New path (Invoke-SaveEditorValue -NewQuery), so what is sent is identical to pressing
        New.

        An empty editor is not offered to be saved.

        Whatever the outcome, Save and Execute end up enabled again: the Save button's handler
        disabled them, and only the asynchronous save re-enables them on the path that reaches it.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    $Private:Tab = Get-ActiveTabSession
    $Private:Proceed = $null -ne $Private:Tab -and ![string]::IsNullOrWhiteSpace((Get-TabEditorText -TabSession $Private:Tab))

    if (-not $Private:Proceed) {
        "The editor is empty: there is nothing to save." | Write-LogOutput -LogType WARNING
    }
    else {
        $Private:Name = Request-NewSqlQueryName -TabSession $Private:Tab
        $Private:Proceed = $null -ne $Private:Name
    }

    if (-not $Private:Proceed) {
        $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $true
        $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $true
        return
    }

    $Script:MainForm.Elements.TextBoxDisplayName.Text = $Private:Name
    "Save ad-hoc query as '{0}'" -f $Private:Name | Write-LogOutput
    Invoke-SaveEditorValue -NewQuery
}
