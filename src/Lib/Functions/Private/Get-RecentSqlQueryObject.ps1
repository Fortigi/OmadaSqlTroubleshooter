# How long a fetched query may be reused by Set-EditorValue. Long enough to cover one load - the
# restore in the cloud-PC log fetched the same query five times within 13 seconds - and short enough
# that a query changed on the tenant by someone else is read again on the next real selection.
$Script:RecentSqlQueryMaxAgeSeconds = 15

function Get-RecentSqlQueryObject {
    <#
    .SYNOPSIS
        The selected query, from a fetch made moments ago when there is one, otherwise from the tenant.

    .DESCRIPTION
        Set-EditorValue runs from five places while a tab loads - the query dropdown's SelectionChanged,
        twice from the editor's own initialisation, the query list refresh, and once per restored tab
        on the same session - and each one fetched the same query synchronously on the UI thread. On a
        cloud PC that was five round trips, about 2.5 s of frozen window, for one answer.

        A fetch is reused for $Script:RecentSqlQueryMaxAgeSeconds, per connection pool and query. The
        cases where the text may have changed in between are handled by clearing, not by waiting:
        Save-Query and Invoke-ExecuteQuery write queries, and Set-SqlConnectionState ends a session on
        disconnect - all three call Clear-RecentSqlQueryObject. (Not on connect: a restored tab fetches
        its query before it connects, and the key already carries the session.)

        Only a real answer is kept. A failed fetch, a 404 or a 401 returns $null from
        Get-SqlQueryObject, which handles them exactly as before, and is asked again next time.

        Save-Query calls Get-SqlQueryObject itself and is deliberately NOT routed through here: it needs
        what is on the tenant right now, to compare against.

    .OUTPUTS
        The query object, or $null.
    #>
    [CmdLetBinding()]
    param()

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

    $Private:Key = "{0}|{1}" -f [string]$Script:RunTimeData.RestMethodParam.SessionKey, [string]$Script:AppConfig.CurrentSqlQuery.DoId

    if ($null -eq $Script:RecentSqlQueryFetch) {
        $Script:RecentSqlQueryFetch = @{}
    }

    $Private:Recent = $Script:RecentSqlQueryFetch[$Private:Key]
    if ($null -ne $Private:Recent -and ([DateTime]::UtcNow - $Private:Recent.FetchedUtc).TotalSeconds -lt $Script:RecentSqlQueryMaxAgeSeconds) {
        "Query {0} was retrieved {1:N1} s ago; reusing it." -f $Script:AppConfig.CurrentSqlQuery.DoId, ([DateTime]::UtcNow - $Private:Recent.FetchedUtc).TotalSeconds | Write-LogOutput -LogType DEBUG
        return $Private:Recent.Result
    }

    $Private:Result = Get-SqlQueryObject
    if ($null -ne $Private:Result) {
        $Script:RecentSqlQueryFetch[$Private:Key] = @{
            Result     = $Private:Result
            FetchedUtc = [DateTime]::UtcNow
        }
    }
    else {
        $Script:RecentSqlQueryFetch.Remove($Private:Key)
    }

    return $Private:Result
}

function Clear-RecentSqlQueryObject {
    <#
    .SYNOPSIS
        Forgets reused query fetches, so the next selection reads the query from the tenant again.

    .DESCRIPTION
        Called wherever the text on the tenant may have changed, or the session has ended: Save-Query
        and Invoke-ExecuteQuery for one query, Set-SqlConnectionState on disconnect for all of them.

    .PARAMETER DoId
        The query to forget. Omitted means every query.

    .OUTPUTS
        None.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DoId
    )

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))

    if ($null -eq $Script:RecentSqlQueryFetch) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($DoId)) {
        $Script:RecentSqlQueryFetch.Clear()
        return
    }

    # Every session's entry for this query: the key starts with the session, and a query saved from one
    # tab is the same object on the tenant for every tab that shows it.
    foreach ($Private:Key in @($Script:RecentSqlQueryFetch.Keys)) {
        if ([string]$Private:Key -like ("*|{0}" -f $DoId)) {
            $Script:RecentSqlQueryFetch.Remove($Private:Key)
        }
    }
}
