function Test-ConnectionSettings {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        $SelectedAuthentication = $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem
        $AuthenticationOption = if ($null -ne $SelectedAuthentication) { $SelectedAuthentication.Content } else { $null }
        $HasCredentials = ![string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxUserName.Text) -and ![string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxPassword.Password)

        $ShouldConnect = Test-ShouldConnect `
            -ReconnectStatus ([int]$Script:RunTimeConfig.ReconnectStatus) `
            -Url $Script:MainForm.Elements.TextBoxURL.Text `
            -AuthenticationOption $AuthenticationOption `
            -HasCredentials $HasCredentials

        Set-SqlConnectionState -Status $ShouldConnect
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
