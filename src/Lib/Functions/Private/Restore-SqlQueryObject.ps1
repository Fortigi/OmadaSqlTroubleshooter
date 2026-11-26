function Restore-SqlQueryObject {
    <#
    .SYNOPSIS
        The query manager's Restore: brings a deleted query back.

    .DESCRIPTION
        Omada deletes data objects softly - it marks them Deleted - and undeletes them with the
        UndeleteDataObject web service, the call the application already makes to recover its own
        temporary query object (New-QueryManagerRequest -Kind RestoreQuery).

        A query that has meanwhile got a namesake that is not deleted would make two queries with one
        name once restored, which the rest of the application refuses to create; so that is asked about
        first. When the tenant cannot be asked, the restore goes ahead: it is the namesake check that is
        unavailable, not the restore.

        The tabs' query lists show the restored query from their next refresh.

    .PARAMETER DoId
        The deleted query.

    .PARAMETER DisplayName
        Its name.

    .OUTPUTS
        [bool] Whether it was restored.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DoId,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName
    )

    if ((Test-SqlQueryNameTaken -Name $DisplayName -ExcludeDoId $DoId) -eq $true) {
        $Private:Anyway = Open-ChoiceForm -Title "Restore query" -Message ("Another query is already named '{0}'. Restore this one as well? There will then be two queries with that name; rename one of them afterwards." -f $DisplayName) -LeftButtonText "Restore" -RightButtonText "Cancel"
        if ($Private:Anyway -ne $true) {
            return $false
        }
    }

    "Restore query {0} ('{1}')" -f $DoId, $DisplayName | Write-LogOutput
    $Private:Response = Invoke-SavedQueryRequest -Request (New-QueryManagerRequest -Kind "RestoreQuery" -Context @{ BaseUrl = $Script:AppConfig.BaseUrl; QueryDoId = $DoId })
    if (-not $Private:Response.Succeeded) {
        "Restoring query '{0}' failed: {1}" -f $DisplayName, $Private:Response.Message | Write-ContainedErrorLog
        return $false
    }

    "Query '{0}' restored." -f $DisplayName | Write-LogOutput
    return $true
}
