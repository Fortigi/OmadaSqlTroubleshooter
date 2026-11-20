function Test-SqlQueryNameTaken {
    <#
    .SYNOPSIS
        Asks the tenant whether another, non-deleted query already carries a name.

    .DESCRIPTION
        The cached query list is not enough to decide this: it can be minutes old, and "Filter my
        queries" hides other people's queries from it. So the tenant is asked, with the name escaped
        as an OData string literal (New-OmadaQueryRequest -Kind QueryNameProbe).

        The query being renamed is not a clash with itself, so -ExcludeDoId is left out of the answer.

    .PARAMETER Name
        The name to look for.

    .PARAMETER ExcludeDoId
        The query being renamed, if any.

    .OUTPUTS
        [bool] $true when taken, $false when free, $null when the tenant could not be asked - the
        caller must not go ahead on a guess.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $ExcludeDoId
    )

    $Private:Request = New-OmadaQueryRequest -Kind "QueryNameProbe" -Context @{
        BaseUrl   = $Script:AppConfig.BaseUrl
        QueryName = $Name
    }

    $Private:Response = Invoke-SavedQueryRequest -Request $Private:Request
    # A GET always answers with a body. None means the wrapper made no request at all (it returns
    # $null when the connection is not ready), which is no answer either.
    if (-not $Private:Response.Succeeded -or $null -eq $Private:Response.Result) {
        "Could not check whether the name '{0}' is in use: {1}" -f $Name, $Private:Response.Message | Write-LogOutput -LogType DEBUG
        return $null
    }

    $Private:Other = @($Private:Response.Result.value | Where-Object { $null -ne $_ -and [string]$_.Id -ne [string]$ExcludeDoId })
    return $Private:Other.Count -gt 0
}
