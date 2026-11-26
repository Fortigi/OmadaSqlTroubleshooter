function Get-OmadaIdentityUserName {
    <#
    .SYNOPSIS
        The signed-in user's name as Omada writes it in "created by" and "changed by": read from the
        user settings page (actusersettingsdlg.aspx) of the active tab's tenant.

    .DESCRIPTION
        The "Only my queries" filters compare that name with who created and last changed each query.
        The main window's filters read it when one of them is switched on; the query manager reads it
        here when one of its own is, so it works whatever the main window's filters are set to.

    .OUTPUTS
        [string] The name, or $null when the page does not give one.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $Script:RunTimeData.RestMethodParam.Uri = "{0}/actusersettingsdlg.aspx?HIDEBACKARRICON=1" -f $Script:AppConfig.BaseUrl
    $Script:RunTimeData.RestMethodParam.Body = $null
    $Script:RunTimeData.RestMethodParam.Method = "GET"
    return ConvertFrom-IdentityUserNamePage -Content (Invoke-OmadaPSWebRequestWrapper)
}

function ConvertFrom-IdentityUserNamePage {
    <#
    .SYNOPSIS
        The user name in the user settings page: its "identityUserName: '<name>'," script value.

    .PARAMETER Content
        The page.

    .OUTPUTS
        [string] The name, or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Content
    )

    if (-not ([string]$Content -match [regex]("identityUserName:.\S+"))) {
        return $null
    }

    $Private:Name = $Matches[0].Split(":")[1].Trim().TrimStart("'").TrimEnd(",").TrimEnd("'")
    return $(if ([string]::IsNullOrWhiteSpace($Private:Name)) { $null } else { $Private:Name })
}
