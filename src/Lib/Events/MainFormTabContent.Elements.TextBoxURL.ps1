$Script:MainForm.Elements.TextBoxURL.Add_GotFocus({
        try {
            $_ | Show-EventInfo
            if (![string]::IsNullOrWhiteSpace($Script:MainForm.Elements.TextBoxURL.Text) -and $Script:MainForm.Elements.TextBlockUrl.Text -like "http*.omada.cloud" -and $Script:MainForm.Elements.TextBlockUrl.Text -ne $Script:CurrentUrl) {
                $Script:CurrentUrl = $Script:MainForm.Elements.TextBlockUrl.Text
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Elements.TextBoxURL.Add_LostFocus({
        $_ | Show-EventInfo

        try {
            Set-OmadaUrl
            Test-ConnectionButton
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Elements.TextBoxURL.Add_PreviewKeyDown({
        param(
            $EventSender,
            $EventArgs
        )
        try {

            $_ | Show-EventInfo

            if ($EventArgs.Key -in ([System.Windows.Input.Key]::Enter, [System.Windows.Input.Key]::Return)) {
                "Enter/Return key intercepted at MainForm level" | Write-LogOutput -LogType VERBOSE

                $EventArgs.Handled = $true

                "Triggering connect" | Write-LogOutput -LogType VERBOSE
                Set-OmadaUrl
                Test-ConnectionButton

                if ($Script:MainForm.Elements.ButtonConnect.IsEnabled) {
                    "Executing connection" | Write-LogOutput -LogType VERBOSE
                    $Script:MainForm.Elements.ButtonConnect.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
