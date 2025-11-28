function Set-OmadaUrl {
    [CmdLetBinding()]
    PARAM()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxURL.Text)) {

            if ($Script:MainWindowForm.Elements.TextBoxURL.Text -notlike "http*") {
                if ($Script:MainWindowForm.Elements.TextBoxURL.Text -notlike "*.*" -and $Script:MainWindowForm.Elements.TextBoxURL.Text -notlike "*.omada.cloud") {
                    $Script:MainWindowForm.Elements.TextBoxURL | Set-TextBlockText -Text "https://$($Script:MainWindowForm.Elements.TextBoxURL.Text).omada.cloud"
                }
                else {
                    $Script:MainWindowForm.Elements.TextBoxURL | Set-TextBlockText -Text "https://$($Script:MainWindowForm.Elements.TextBoxURL.Text)"
                }
            }

            $Uri = [System.Uri]::new($Script:MainWindowForm.Elements.TextBoxURL.Text.Trim())

            if ($Uri.IsAbsoluteUri -and ($Uri.Scheme -eq 'http' -or $Uri.Scheme -eq 'https')) {
        ("Input Url {0} is valid." -f $Uri.IsAbsoluteUri) | Write-LogOutput -LogType DEBUG
            }
            else {
                $null | Set-ConfigProperty -Property "BaseUrl"
                $Script:MainWindowForm.Elements.TextBoxURL.Text = $null
                "Input Url {0} is not valid." -f $Script:MainWindowForm.Elements.TextBoxURL.Text.Trim() | Write-LogOutput -LogType ERROR
                Set-Disconnected
                return
            }

            try {
                $DnsResult = Resolve-DnsName -Name $Uri.Host -QuickTimeout -ErrorAction SilentlyContinue
                if (($DnsResult | Measure-Object).Count -le 0) {
                    "DNS resolution for {0} failed!" -f $Uri.Host | Write-LogOutput -LogType ERROR
                    Set-Disconnected
                    return
                }
            }
            catch {
                $null | Set-ConfigProperty -Property "BaseUrl"
                $Script:MainWindowForm.Elements.TextBoxURL.Text = $null
                $Script:MainWindowForm.Elements.TextBlockStatusBarUrl.Text = $null
                "Endpoint {0} not found!" -f $Uri.AbsoluteUri | Write-LogOutput -LogType ERROR
                Set-Disconnected
            }

            $Uri.AbsoluteUri.TrimEnd("/") | Set-ConfigProperty -Property "BaseUrl"

            if ($Script:CurrentUrl -ne $Script:AppConfig.BaseUrl) {
                "Omada Url set to: {0}" -f $Script:AppConfig.BaseUrl | Write-LogOutput -LogType DEBUG
                $Script:CurrentUrl = $Script:AppConfig.BaseUrl
                # if ($Script:RunTimeConfig.AuthenticationSet) {
                #     "Authentication is set, force update query list!" | Write-LogOutput -LogType DEBUG
                #     #Update-QueryList -ForceRefresh
                # }
                $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.IsEnabled = $true
            }
            elseif ([string]::IsNullOrEmpty($Script:AppConfig.BaseUrl)) {
                "Omada Url is empty!" | Write-LogOutput -LogType DEBUG
                Set-Disconnected
            }
            else {
                "Omada Url maintained: {0}" -f $Script:AppConfig.BaseUrl | Write-LogOutput -LogType DEBUG
                $Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.IsEnabled = $true
            }
        }
        else {
            Reset-Application
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
