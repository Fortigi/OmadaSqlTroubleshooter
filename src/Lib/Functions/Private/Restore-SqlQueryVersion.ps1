function Restore-SqlQueryVersion {
    <#
    .SYNOPSIS
        Puts an older version of a query, from its history, in the editor of the tab that holds it.

    .DESCRIPTION
        The history window's Restore. For the active tab's own query it does what Restore always did -
        the version goes into the editor through window.setEditorValue, and CurrentQueryText follows -
        with one deliberate change: the tab is now marked as changed. Restore used to leave the tab
        clean on purpose (a programmatic load is not a user edit), but a version that is only in the
        editor is not saved, and with closing now offering to save unsaved work, a clean flag would
        let a restored version be lost on close without a word.

        For any other query (history opened from the query manager) the version goes into the tab that
        holds the query, or into a new tab opened for it (Open-SqlQueryInTab -RestoreText), and the
        query manager is asked to close so that tab can be seen and its editor can load.

        Nothing is saved: the restored version is an unsaved change until the user saves it.

    .PARAMETER DoId
        The query the version belongs to.

    .PARAMETER QueryName
        Its name.

    .PARAMETER Text
        The version's text.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DoId,

        [Parameter(Mandatory = $false)]
        [string]$QueryName,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    if (-not [string]::IsNullOrWhiteSpace($DoId) -and $DoId -ne [string]$Script:AppConfig.CurrentSqlQuery.DoId) {
        $null = Open-SqlQueryInTab -DoId $DoId -DisplayName $QueryName -RestoreText $Text
        Request-QueryManagerClose
        "Query '{0}' restored in its tab; save it to keep it." -f $QueryName | Write-LogOutput
        return
    }

    if ($null -eq $Script:Webview.Object.CoreWebView2) {
        "The editor is not ready; nothing was restored." | Write-LogOutput -LogType WARNING
        return
    }

    Push-ToEditor -ScriptToExecute ("window.setEditorValue({0});" -f (ConvertTo-JavaScriptLiteral -Value $Text))
    $Script:RunTimeData.CurrentQueryText = $Text

    $Private:Tab = Get-ActiveTabSession
    if ($null -ne $Private:Tab) {
        Set-TabEditorText -TabSession $Private:Tab -Text $Text
        $Private:Tab.IsDirty = $true
        Update-TabHeaderTitle -TabSession $Private:Tab
    }
    "Query restored to the editor; save it to keep it." | Write-LogOutput
}
