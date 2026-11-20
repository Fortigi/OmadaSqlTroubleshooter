function Test-AdHocQuery {
    <#
    .SYNOPSIS
        Whether a tab's editor holds an ad-hoc query: SQL that is not backed by a saved query object.

    .DESCRIPTION
        A tab is ad-hoc whenever no saved query is selected, which is how every tab starts: the user
        can type a query and execute it without pressing New first. Executing an ad-hoc query runs it
        through the temporary TMP_<InstanceGuid> object the execute pipeline already uses for an
        executed selection, so nothing the user owns is created or changed on the tenant.

        The DoId is the test, not the query dropdown. 0 counts as "no query": Reset-Application clears
        the selection with `$null, $null | Set-ConfigProperty -Property "CurrentSqlQuery"`, and the
        PSObject branch of Set-ConfigProperty casts that $null to [int], which is 0. No Omada data
        object has id 0, so treating it as a real query would execute and save against an object that
        does not exist.

    .PARAMETER QueryDoId
        The selected query's DoId, as $Script:AppConfig.CurrentSqlQuery.DoId holds it - a number, a
        string, or $null.

    .OUTPUTS
        [bool] $true when there is no saved query behind the editor.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $QueryDoId
    )

    $Private:Text = [string]$QueryDoId
    if ([string]::IsNullOrWhiteSpace($Private:Text)) {
        return $true
    }

    return $Private:Text.Trim() -eq "0"
}
