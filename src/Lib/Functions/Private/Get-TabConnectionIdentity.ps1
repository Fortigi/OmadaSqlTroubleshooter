function Get-TabConnectionIdentity {
    <#
    .SYNOPSIS
    Returns a tab's connection identity - the tuple that decides whether two tabs "match" for
    authentication sharing / auto-connect: tenant base url, authentication method, username,
    password, and the Entra application id uri / tenant id.

    .DESCRIPTION
    Produces a normalized object plus a stable Key (SHA256 of the normalized tuple). Two tabs share
    authentication when their Keys are equal. IsEmpty is true when none of the identity fields are
    set. The Key is also used as the OmadaWeb.PS SessionKey so matching tabs reuse the same session
    bucket (one login serves them all) instead of each getting an isolated per-tab session.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession
    )
    try {
        $Normalize = {
            param($Value)
            if ($null -eq $Value) { return "" }
            return $Value.ToString().Trim()
        }

        $BaseUrl = (& $Normalize $TabSession.AppConfig.BaseUrl).TrimEnd("/").ToLowerInvariant()
        $Auth = & $Normalize $TabSession.AppConfig.LastAuthentication
        $UserName = & $Normalize $TabSession.AppConfig.UserName

        $Password = ""
        try {
            $Password = & $Normalize $TabSession.Elements.TextBoxPassword.Password
        }
        catch {
            $Password = ""
        }

        $AppIdUri = & $Normalize $TabSession.AppConfig.EntraApplicationIdUri
        $TenantId = & $Normalize $TabSession.AppConfig.EntraIdTenantId

        $IsEmpty = [string]::IsNullOrWhiteSpace($BaseUrl) -and [string]::IsNullOrWhiteSpace($UserName) -and [string]::IsNullOrWhiteSpace($Password) -and [string]::IsNullOrWhiteSpace($AppIdUri) -and [string]::IsNullOrWhiteSpace($TenantId)

        $Raw = "{0}|{1}|{2}|{3}|{4}|{5}" -f $BaseUrl, $Auth, $UserName, $Password, $AppIdUri, $TenantId
        $Sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $Bytes = $Sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Raw))
            $Key = "identity:" + (($Bytes | ForEach-Object { $_.ToString("x2") }) -join "")
        }
        finally {
            $Sha.Dispose()
        }

        return [PSCustomObject]@{
            BaseUrl  = $BaseUrl
            Auth     = $Auth
            UserName = $UserName
            Password = $Password
            AppIdUri = $AppIdUri
            TenantId = $TenantId
            IsEmpty  = $IsEmpty
            Key      = $Key
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        return $null
    }
}
