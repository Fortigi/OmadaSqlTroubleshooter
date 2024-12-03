$Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.Add_SelectionChanged({
    $_ | Show-EventInfo

    Set-AuthenticationOption
    "Changed authentication option to: {0}" -f $Script:AppConfig.LastAuthentication | Write-LogOutput -LogType DEBUG

    if ($Script:AuthenticationNotSet -eq $true -and ![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxURL.Text)) {
        Set-OmadaUrl
    }
    Test-ConnectionSettings

})
