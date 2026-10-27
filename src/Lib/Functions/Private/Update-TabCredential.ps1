function Update-TabCredential {
    <#
    .SYNOPSIS
    Creates, updates or clears the active tab's credential from the username and password boxes.

    .DESCRIPTION
    The single place that sets $Script:RunTimeData.RestMethodParam.Credential from the UI, shared by
    the username and password LostFocus handlers and the tab restore, so the three cannot disagree
    about when a credential exists. The rules live in Resolve-TabCredential; this function reads the
    form, applies the result and tells the user what it means.

    An empty password is not an error: for Browser (on WebView2) and WebView2 a credential carrying
    only the username is created, so the sign-in uses that account and can be completed passwordless.

    .OUTPUTS
    The Resolve-TabCredential result.
    #>
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        $SelectedAuthentication = $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem
        $AuthenticationOption = if ($null -ne $SelectedAuthentication) { [string]$SelectedAuthentication.Content } else { $null }

        # SecurePassword hands over a copy of the password without a plaintext string. A whitespace-only
        # password counts as no password, as everywhere else the password box is tested.
        $Password = $null
        if (![string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxPassword.Password)) {
            $Password = $Script:MainForm.Elements.TextBoxPassword.SecurePassword
        }

        $Resolved = Resolve-TabCredential `
            -UserName $Script:MainForm.Elements.TextBoxUserName.Text `
            -Password $Password `
            -AuthenticationOption $AuthenticationOption `
            -UseWebView2Auth ([bool]$Script:RunTimeConfig.UseWebView2Auth)

        if ($null -ne $Resolved.Credential) {
            "Create/Update {0} credential with username {1}" -f $Resolved.Mode.ToLowerInvariant(), $Resolved.Credential.UserName | Write-LogOutput -LogType DEBUG
            if (!$Script:RunTimeData.RestMethodParam.ContainsKey("Credential")) {
                $Script:RunTimeData.RestMethodParam.Add("Credential", $null)
            }
            # Said once per change into passwordless, not on every focus change or tab restore.
            if (Test-NewPasswordlessCredential -Previous $Script:RunTimeData.RestMethodParam.Credential -Current $Resolved.Credential) {
                "No password entered: {0} will sign in without a password. A password is only needed for password based authentication; at sign-in, complete it in the sign-in window with a passwordless method or by typing the password there." -f $Resolved.Credential.UserName | Write-LogOutput -LogType INFO -SkipDialog
            }
            $Script:RunTimeData.RestMethodParam.Credential = $Resolved.Credential
            return $Resolved
        }

        if ($Script:RunTimeData.RestMethodParam.ContainsKey("Credential") -and $null -ne $Script:RunTimeData.RestMethodParam.Credential) {
            "Clear credential: {0}" -f $Resolved.Reason | Write-LogOutput -LogType DEBUG
        }
        if ($Script:RunTimeData.RestMethodParam.ContainsKey("Credential")) {
            $Script:RunTimeData.RestMethodParam.Credential = $null
            if ($AuthenticationOption -ne "OAuth") {
                $Script:RunTimeData.RestMethodParam.Remove("Credential")
            }
        }

        if (![string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxUserName.Text)) {
            # A username was entered but cannot be used on its own - say why, since the field
            # suggests otherwise.
            "{0}; the username is not used for authentication" -f $Resolved.Reason | Write-LogOutput -LogType VERBOSE
        }
        return $Resolved
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
