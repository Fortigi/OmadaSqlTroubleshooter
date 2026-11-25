function New-SqlQueryObject {
    <#
    .SYNOPSIS
        Creates a new query object on the tenant, from the query manager: a name, and an empty query.

    .DESCRIPTION
        The name is asked for (Read-QueryNameInput) and checked against the manager's list and then
        the tenant (Test-SqlQueryNameTaken), exactly as for Save as. The query text is a one-line SQL
        comment naming the query rather than empty, so a tenant that requires a value accepts it and
        the editor opens on something recognisable. The data connection is the active tab's.

        The new query is added to every connected tab of the pool (Add-QueryToConnectedPoolTabs).

        Needs the Create right on the OData auth element; a refusal is reported with the tenant's
        message.

    .PARAMETER ExistingNames
        Names of the queries the manager shows.

    .OUTPUTS
        [PSCustomObject] @{ DoId; DisplayName } of the new query, or $null when none was created.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string[]]$ExistingNames = @()
    )

    try {
        $Private:Name = Read-QueryNameInput -Title "New query" -Message "Name of the new query:" -ExistingNames $ExistingNames -OkText "Create"
        if ($null -eq $Private:Name) {
            return $null
        }

        $Private:Taken = Test-SqlQueryNameTaken -Name $Private:Name.Name
        if ($false -ne $Private:Taken) {
            Write-SqlQueryNameUnavailable -Name $Private:Name.Name -Taken $Private:Taken
            return $null
        }

        $Private:Response = Invoke-SavedQueryRequest -Request (New-QueryManagerRequest -Kind "CreateQuery" -Context @{
                BaseUrl            = $Script:AppConfig.BaseUrl
                QueryName          = $Private:Name.Name
                QueryText          = "-- {0}" -f $Private:Name.Name
                DataConnectionDoId = $Script:AppConfig.CurrentDataConnection.DoId
            })

        if (-not $Private:Response.Succeeded -or $null -eq $Private:Response.Result -or $null -eq $Private:Response.Result.Id) {
            "Creating query '{0}' failed: {1}" -f $Private:Name.Name, $Private:Response.Message | Write-ContainedErrorLog
            return $null
        }

        $Private:Created = [PSCustomObject]@{
            DoId        = [string]$Private:Response.Result.Id
            DisplayName = Get-SavedQueryDisplayName -Result $Private:Response.Result -FallbackName $Private:Name.Name
        }
        Add-QueryToConnectedPoolTabs -DoId $Private:Created.DoId -DisplayName $Private:Created.DisplayName -FullName ("{0} - {1}" -f $Private:Created.DisplayName, $Private:Created.DoId)
        "Query '{0}' created." -f $Private:Created.DisplayName | Write-LogOutput
        return $Private:Created
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        return $null
    }
}
