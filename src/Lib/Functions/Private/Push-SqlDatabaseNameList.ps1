function Push-SqlDatabaseNameList {
    <#
    .SYNOPSIS
        Tells the Monaco editor which names are data connections, and which one the tab is connected
        to.

    .DESCRIPTION
        The editor decides for itself when a dot chain names a database - that is what makes
        "[Other]." complete without a round trip per keystroke - and it cannot do that without
        knowing the names (issue #158). It also needs to know the ACTIVE connection's name, so that
        "[ThisDatabase]." is answered from the setSchema model it already holds rather than by asking
        for a schema it will never be sent through setSchemaForDatabase.

        Pushed from the two moments the list is known to be current: a schema response for the active
        connection, and the completion of a data connection list update. Both are needed because
        either can happen first - the schema can land before the list has loaded - and neither of
        them may make a request to catch the other up.

        The name is the data connection's NAME, not its "{Name} - {DoId}" display text, because the
        name is what the user writes between brackets.

    .PARAMETER ActiveDataConnectionDoId
        The DoId to report as the active one. Omitted or empty falls back to the tab's current data
        connection, which is what the list-update caller wants.

    .PARAMETER OnCompletedScriptBlock
        Passed through to Invoke-ExecuteScriptAsync.

    .OUTPUTS
        None.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ActiveDataConnectionDoId,

        [Parameter(Mandatory = $false, Position = 1)]
        [AllowNull()]
        [scriptblock]$OnCompletedScriptBlock
    )

    # No tracer preamble: the payload names the tenant's databases (issue #61 section 5).

    try {
        # -NoRefresh: this runs on the UI thread, from a request completion. A synchronous tenant
        # refresh hidden inside a push of metadata would block the window, and it is unnecessary -
        # the list-update caller below runs this again the moment the list does arrive.
        #
        # Not wrapped in @() - the function returns its array through the ", $array" idiom, and
        # wrapping it again nests the array one level deeper.
        $Private:Reference = Get-DataConnectionReferenceList -OptionList (Get-DataConnectionOptionText -NoRefresh)

        # Nulls filtered out: with no connections at all, .Name yields $null and the payload would be
        # "[null]" rather than "[]".
        $Private:NameJson = @($Private:Reference.Name | Where-Object { ![string]::IsNullOrWhiteSpace($_) }) | ConvertTo-Json -Depth 2 -AsArray

        $Private:ActiveDoId = if (![string]::IsNullOrWhiteSpace($ActiveDataConnectionDoId)) {
            $ActiveDataConnectionDoId
        }
        else {
            [string]$Script:AppConfig.CurrentDataConnection.DoId
        }

        $Private:ActiveName = @($Private:Reference | Where-Object { $_.DoId -eq $Private:ActiveDoId }).Name | Select-Object -First 1
        $Private:ActiveNameLiteral = ConvertTo-JavaScriptLiteral -Value ([string]$Private:ActiveName)

        "Push {0} data connection name(s) to the Monaco editor." -f @($Private:Reference).Count | Write-LogOutput -LogType DEBUG
        Invoke-ExecuteScriptAsync -ScriptToExecute "setDatabaseNames($Private:NameJson, $Private:ActiveNameLiteral);" -OnCompletedScriptBlock $OnCompletedScriptBlock
    }
    catch {
        # Failing to tell the editor which names are databases costs cross-database completion, not
        # the user's work, so it must never interrupt them.
        $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}
