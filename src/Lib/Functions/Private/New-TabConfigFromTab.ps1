function New-TabConfigFromTab {
    <#
    .SYNOPSIS
        A tab config (for New-TabSession -RestoreFrom) that connects like an existing tab.

    .DESCRIPTION
        Shared by duplicating a tab (Complete-DuplicateTab) and opening a query in a new tab
        (Open-SqlQueryInTab): same tenant, same authentication and credential, same data connection
        and output mode, a new id. A tab with the same credential shares the source's connection pool,
        so a connected source means the new tab reconnects without signing in again.

        New-TabSession -RestoreFrom expects the password as a DPAPI-protected string (it decrypts it
        back for the password box), so the source's live password is protected again here. It is only
        persisted when the source has Save password ticked, exactly as before.

    .PARAMETER SourceTab
        The tab to copy the connection from.

    .PARAMETER CurrentSqlQuery
        The saved query the new tab should select: @{ DoId; DisplayName; FullName }. Omitted, the new
        tab holds a new, unsaved query.

    .OUTPUTS
        [PSCustomObject] A tab config.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        $SourceTab,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $CurrentSqlQuery
    )

    $Private:Password = $null
    $Private:SourcePassword = $SourceTab.Elements.TextBoxPassword.Password
    if (![string]::IsNullOrWhiteSpace($Private:SourcePassword)) {
        $Private:Password = $Private:SourcePassword | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
    }

    if ($null -eq $CurrentSqlQuery) {
        $CurrentSqlQuery = [PSCustomObject]@{ DoId = $null; DisplayName = $null; FullName = $null }
    }

    return [PSCustomObject]@{
        Id                    = (New-Guid).Guid
        DisplayName           = $CurrentSqlQuery.DisplayName
        BaseUrl               = $SourceTab.AppConfig.BaseUrl
        CurrentSqlQuery       = $CurrentSqlQuery
        LastAuthentication    = $SourceTab.AppConfig.LastAuthentication
        UserName              = $SourceTab.AppConfig.UserName
        Password              = $Private:Password
        EntraApplicationIdUri = $SourceTab.AppConfig.EntraApplicationIdUri
        EntraIdTenantId       = $SourceTab.AppConfig.EntraIdTenantId
        MyCreatedQueriesOnly  = [bool]$SourceTab.AppConfig.MyCreatedQueriesOnly
        MyUpdatedQueriesOnly  = [bool]$SourceTab.AppConfig.MyUpdatedQueriesOnly
        SavePassword          = [bool]$SourceTab.Elements.CheckboxSavePassword.IsChecked
        IdentityUserName      = $SourceTab.AppConfig.IdentityUserName
        CurrentDataConnection = $SourceTab.AppConfig.CurrentDataConnection
        ResultOutputMode      = $SourceTab.AppConfig.ResultOutputMode
    }
}
