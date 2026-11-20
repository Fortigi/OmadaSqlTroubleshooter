function Update-SavedQueryCommandState {
    <#
    .SYNOPSIS
        Enables Rename and Delete exactly when the active tab is connected and has a saved query
        selected.

    .DESCRIPTION
        Both act on a saved query object, so neither means anything for an ad-hoc query or while
        disconnected. Called whenever that can change: a query is selected or cleared, and the
        connection state changes (Set-SqlQueryFunctionState).

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    $Private:Enabled = [bool]$Script:ConnectionStatus -and -not (Test-AdHocQuery -QueryDoId $Script:AppConfig.CurrentSqlQuery.DoId) -and $null -ne $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem

    foreach ($Private:Name in @("ButtonRenameQuery", "ButtonDeleteQuery")) {
        $Private:Button = $Script:MainForm.Elements.$Private:Name
        if ($null -ne $Private:Button) {
            $Private:Button.IsEnabled = $Private:Enabled
        }
    }
}
