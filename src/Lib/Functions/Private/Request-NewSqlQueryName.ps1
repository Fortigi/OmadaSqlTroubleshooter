function Request-NewSqlQueryName {
    <#
    .SYNOPSIS
        Asks for the name to save an ad-hoc query under, and makes sure the tenant does not already
        have a query with it.

    .DESCRIPTION
        The suggestion is the Display name box when it holds something, otherwise the next free
        "Query{#}" (Get-UniqueQueryName) starting at the tab's own number - the same name a duplicated
        tab is given.

    .PARAMETER TabSession
        The tab whose query is being saved. Its Elements, cached query list and open order are read.

    .PARAMETER Message
        What the dialog says above the name box.

    .OUTPUTS
        [string] The name, or $null when the user cancelled or the name cannot be used (the reason has
        been reported).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession,

        [string]$Message = "Save the ad-hoc query in Omada as:"
    )

    $Private:Existing = @(Get-CachedQueryName -QueryList $TabSession.RunTimeData.QueryListCache.QueryList)

    $Private:Default = [string]$TabSession.Elements.TextBoxDisplayName.Text
    if ([string]::IsNullOrWhiteSpace($Private:Default)) {
        $Private:Default = Get-UniqueQueryName -ExistingNames $Private:Existing -StartNumber ([int]$TabSession.OpenOrder)
    }

    $Private:Name = Read-QueryNameInput -Title "Save query" -Message $Message -DefaultName $Private:Default -ExistingNames $Private:Existing -OkText "Save"
    if ($null -eq $Private:Name) {
        return $null
    }

    $Private:Taken = Test-SqlQueryNameTaken -Name $Private:Name.Name
    if ($false -ne $Private:Taken) {
        Write-SqlQueryNameUnavailable -Name $Private:Name.Name -Taken $Private:Taken
        return $null
    }

    return $Private:Name.Name
}
