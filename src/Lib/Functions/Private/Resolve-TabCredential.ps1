function Resolve-TabCredential {
    <#
    .SYNOPSIS
    Decides which credential, if any, a tab passes to OmadaWeb.PS for the username and password the
    user entered.

    .DESCRIPTION
    Pure decision behind Update-TabCredential, kept separate so the rules can be unit tested without
    WPF.

    A password is only needed for password based authentication. For an interactive WebView2 sign-in
    the username alone is enough: OmadaWeb.PS sends it to Entra ID as the account to sign in with
    (login_hint) and, when the credential carries no password, waits in the sign-in window for the
    user to finish with a passwordless method (Windows Hello, a FIDO2 key, Authenticator) or by typing
    the password there. A credential with an empty password is therefore a valid way to name the
    account without storing a secret.

    Modes:
    - Password      Username and password are set: a normal credential.
    - Passwordless  Username set, password empty, and the sign-in can complete without one: a
                    credential that carries the username and an empty password.
    - None          No credential. Reason says why.

    Passwordless is refused, and no credential is created, when:
    - the authentication option needs the secret itself (OAuth client secret, Basic, Windows);
    - the sign-in runs on the Selenium engine ("Browser" without -UseWebView2Auth), which submits the
      password field with whatever the credential holds and would post an empty password.

    Passwordless sign-in needs OmadaWeb.PS 2026.9.23.47 or higher, which is the application's
    minimum, so it is not checked here.

    .PARAMETER UserName
    The username as entered.

    .PARAMETER Password
    The password as a SecureString (the password box's SecurePassword), so the plaintext never passes
    through here. Null or empty means "no password". The caller passes $null for a whitespace-only
    password, matching how the rest of the application tests the password box.

    .PARAMETER AuthenticationOption
    The authentication option as shown in the combo box (Browser, WebView2, OAuth, Browser-InPrivate,
    WebView2-InPrivate).

    .PARAMETER UseWebView2Auth
    Whether "Browser" runs on WebView2 ($Script:RunTimeConfig.UseWebView2Auth).

    .OUTPUTS
    [PSCustomObject] with Mode, Credential ([PSCredential] or $null) and Reason.
    #>
    [CmdLetBinding()]
    param(
        [AllowNull()][AllowEmptyString()]
        [string]$UserName,
        [AllowNull()]
        [securestring]$Password,
        [AllowNull()][AllowEmptyString()]
        [string]$AuthenticationOption,
        [bool]$UseWebView2Auth
    )

    $Result = [PSCustomObject]@{
        Mode       = "None"
        Credential = $null
        Reason     = $null
    }

    if ([string]::IsNullOrWhiteSpace($UserName)) {
        $Result.Reason = "Username is empty"
        return $Result
    }

    if ($null -ne $Password -and $Password.Length -gt 0) {
        $Result.Mode = "Password"
        $Result.Credential = [System.Management.Automation.PSCredential]::new($UserName, $Password)
        return $Result
    }

    if ($AuthenticationOption -in @("OAuth", "Basic", "Windows")) {
        $Result.Reason = "{0} authentication requires a password" -f $AuthenticationOption
        return $Result
    }

    $Engine = $AuthenticationOption -replace "-InPrivate$", ""
    if ($Engine -eq "Browser" -and -not $UseWebView2Auth) {
        $Result.Reason = "Signing in with a username and no password requires WebView2; the Browser option without WebView2 would submit an empty password"
        return $Result
    }

    if ($Engine -notin @("Browser", "WebView2")) {
        $Result.Reason = "Authentication option '{0}' does not support signing in without a password" -f $AuthenticationOption
        return $Result
    }

    # [securestring]::new() is an empty, valid SecureString. ConvertTo-SecureString cannot be used
    # here: it refuses an empty string.
    $Result.Mode = "Passwordless"
    $Result.Credential = [System.Management.Automation.PSCredential]::new($UserName, [securestring]::new())
    return $Result
}
