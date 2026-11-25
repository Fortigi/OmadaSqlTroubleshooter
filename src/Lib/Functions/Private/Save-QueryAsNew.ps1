function Save-QueryAsNew {
    <#
    .SYNOPSIS
        Saves the active tab's editor as a new query object, under a name asked for in a pop-up.

    .DESCRIPTION
        Two commands end here:

          Save     on an ad-hoc query: there is no object to update, so saving creates one.
          Save as  on any query: the editor is saved as another query, and the tab then holds that
                   new query; the original is left as it was saved.

        The name is asked for (Request-NewSqlQueryName) and checked with the tenant, then handed to
        Save-Query as RunTimeData.PendingQueryName, and the save itself is the asynchronous create
        path (Invoke-SaveEditorValue -NewQuery), which reads the editor fresh.

        An empty editor is not offered to be saved.

        Whatever the outcome, Save and Execute end up enabled again: the Save button's handler
        disabled them, and only the asynchronous save re-enables them on the path that reaches it.

    .PARAMETER DefaultName
        The name to suggest. Omitted, Request-NewSqlQueryName suggests the tab's proposed name or the
        next free Query{#}.

    .PARAMETER Message
        What the name prompt says.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DefaultName,

        [string]$Message = "Save the ad-hoc query in Omada as:"
    )

    $Private:Tab = Get-ActiveTabSession
    $Private:Proceed = $null -ne $Private:Tab -and ![string]::IsNullOrWhiteSpace((Get-TabEditorText -TabSession $Private:Tab))

    if (-not $Private:Proceed) {
        "The editor is empty: there is nothing to save." | Write-LogOutput -LogType WARNING
    }
    else {
        $Private:Name = Request-NewSqlQueryName -TabSession $Private:Tab -Message $Message -DefaultName $DefaultName
        $Private:Proceed = $null -ne $Private:Name
    }

    if (-not $Private:Proceed) {
        $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled = $true
        $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled = $true
        return
    }

    $Script:RunTimeData.PendingQueryName = $Private:Name
    "Save the editor as new query '{0}'" -f $Private:Name | Write-LogOutput
    Invoke-SaveEditorValue -NewQuery
}

function Save-SqlQueryAs {
    <#
    .SYNOPSIS
        Save as: saves the active tab's editor as another, new query.

    .DESCRIPTION
        For a saved query the suggested name is the next free numbered variant of its name
        (Get-IncrementedQueryName: "Accounts" suggests "Accounts1"); an ad-hoc query is offered its
        proposed name or Query{#}, exactly like Save.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    $Private:Default = $null
    if (-not (Test-AdHocQuery -QueryDoId $Script:AppConfig.CurrentSqlQuery.DoId)) {
        $Private:Existing = @(Get-CachedQueryName -QueryList $Script:RunTimeData.QueryListCache.QueryList)
        $Private:Default = Get-IncrementedQueryName -BaseName $Script:RunTimeData.CurrentSqlQuery.DisplayName -ExistingNames $Private:Existing
    }

    Save-QueryAsNew -DefaultName $Private:Default -Message "Save the query in Omada as a new query, named:"
}
