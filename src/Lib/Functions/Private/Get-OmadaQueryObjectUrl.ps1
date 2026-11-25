function Get-OmadaQueryObjectUrl {
    <#
    .SYNOPSIS
        The address of a query object's own page in Omada.

    .DESCRIPTION
        dataobjdlg.aspx?DOID=<id> is Omada's data object page; this application already reads the
        data connection options from it (Update-DataConnectionList). The address is handed to the
        operating system to open, so it is built only from a tenant URL that is an absolute http(s)
        address and an id that is a number: anything else yields nothing rather than a URL that could
        launch something other than a web page.

    .PARAMETER BaseUrl
        The tenant URL.

    .PARAMETER DoId
        The query object's id.

    .OUTPUTS
        [string] The address, or $null when either part is not usable.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$BaseUrl,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DoId
    )

    $Private:Uri = $null
    if (-not [System.Uri]::TryCreate($BaseUrl, [System.UriKind]::Absolute, [ref]$Private:Uri) -or $Private:Uri.Scheme -notin @("https", "http")) {
        return $null
    }

    if ([string]$DoId -notmatch '^\d+$') {
        return $null
    }

    return "{0}/dataobjdlg.aspx?DOID={1}" -f $BaseUrl.TrimEnd("/"), $DoId
}

function Open-OmadaQueryObject {
    <#
    .SYNOPSIS
        Opens a query object's page in Omada in the default browser.

    .DESCRIPTION
        The browser has its own session with Omada, separate from this application's, so it may ask
        the user to sign in.

    .PARAMETER DoId
        The query object's id.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DoId
    )

    $Private:Url = Get-OmadaQueryObjectUrl -BaseUrl $Script:AppConfig.BaseUrl -DoId $DoId
    if ($null -eq $Private:Url) {
        "Cannot open query {0} in Omada: the tenant URL or the query id is not usable." -f $DoId | Write-LogOutput -LogType WARNING
        return
    }

    "Opening {0}" -f $Private:Url | Write-LogOutput -LogType DEBUG
    Start-Process -FilePath $Private:Url
}
