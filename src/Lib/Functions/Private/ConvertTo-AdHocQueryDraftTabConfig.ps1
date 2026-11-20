function ConvertTo-AdHocQueryDraftTabConfig {
    <#
    .SYNOPSIS
        The connection settings an ad-hoc query draft carries, so a tab can be reopened for it.

    .DESCRIPTION
        The same shape New-TabSession -RestoreFrom takes, and the same fields Save-TabSessions
        persists, with two deliberate differences:

          - No password, saved or not. The draft store is rewritten while the user types, far more
            often than tabs.clixml, and is a plain JSON file; it is no place for a credential, even a
            DPAPI-protected one. A tab reopened from a draft asks for the password like a new tab.
          - No selected query. A draft is by definition an ad-hoc query.

        The Display name the user typed is kept as the tab's DisplayName, so the reopened tab carries
        the name it had and saving it later suggests that name.

    .PARAMETER TabId
        The tab's id, kept so the draft and the tab it reopens stay matched.

    .PARAMETER AppConfig
        The tab's AppConfig.

    .PARAMETER DisplayName
        What the tab's Display name box holds.

    .OUTPUTS
        [PSCustomObject] A tab config for New-TabSession -RestoreFrom.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TabId,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $AppConfig,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DisplayName
    )

    return [PSCustomObject]@{
        Id                    = $TabId
        DisplayName           = $(if ([string]::IsNullOrWhiteSpace($DisplayName)) { $null } else { $DisplayName.Trim() })
        BaseUrl               = $AppConfig.BaseUrl
        CurrentSqlQuery       = [PSCustomObject]@{ DoId = $null; DisplayName = $null; FullName = $null }
        LastAuthentication    = $AppConfig.LastAuthentication
        UserName              = $AppConfig.UserName
        Password              = $null
        EntraApplicationIdUri = $AppConfig.EntraApplicationIdUri
        EntraIdTenantId       = $AppConfig.EntraIdTenantId
        MyCreatedQueriesOnly  = [bool]$AppConfig.MyCreatedQueriesOnly
        MyUpdatedQueriesOnly  = [bool]$AppConfig.MyUpdatedQueriesOnly
        SavePassword          = $false
        IdentityUserName      = $AppConfig.IdentityUserName
        CurrentDataConnection = $AppConfig.CurrentDataConnection
        ResultOutputMode      = $AppConfig.ResultOutputMode
    }
}
