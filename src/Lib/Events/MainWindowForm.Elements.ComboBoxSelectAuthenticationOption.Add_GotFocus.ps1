$Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.Add_GotFocus({
    $_ | Show-EventInfo
    if ($null -eq $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem) {
        $Script:AuthenticationNotSet = $true
    }
})
