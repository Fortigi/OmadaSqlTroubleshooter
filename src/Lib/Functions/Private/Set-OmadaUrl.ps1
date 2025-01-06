function Set-OmadaUrl {

    try {

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
                $Null | Invoke-ConfigSetting -Property "BaseUrl"
                $Script:MainWindowForm.Elements.TextBoxURL.Text = $Null
                "Input Url {0} is not valid." -f $Script:MainWindowForm.Elements.TextBoxURL.Text.Trim() | Write-LogOutput -LogType ERROR
                return
            }

            try {
                $DnsResult = Resolve-DnsName -Name $Uri.Host -QuickTimeout -ErrorAction SilentlyContinue
                if (($DnsResult | Measure-Object).Count -le 0) {
                    "DNS resolution for {0} failed!" -f $Uri.Host | Write-LogOutput -LogType ERROR
                    return
                }
            }
            catch {
                $Null | Invoke-ConfigSetting -Property "BaseUrl"
                $Script:MainWindowForm.Elements.TextBoxURL.Text = $Null
                $Script:MainWindowForm.Elements.TextBlockUrl.Text = $Null
                "Endpoint {0} not found!" -f $Uri.AbsoluteUri | Write-LogOutput -LogType ERROR
            }

            $Uri.AbsoluteUri.TrimEnd("/") | Invoke-ConfigSetting -Property "BaseUrl"

            if ($Script:CurrentUrl -ne $Script:AppConfig.BaseUrl) {
                "Omada Url set to: {0}" -f $Script:AppConfig.BaseUrl | Write-LogOutput -LogType DEBUG
                $Script:CurrentUrl = $Script:AppConfig.BaseUrl
                if ($Script:RunTimeConfig.AuthenticationSet) {
                    "Authentication is set, force update query list!" | Write-LogOutput -LogType DEBUG
                    Update-QueryList -ForceRefresh
                }
            }
            elseif([string]::IsNullOrEmpty($Script:AppConfig.BaseUrl)) {
                "Omada Url is empty!" | Write-LogOutput -LogType DEBUG
            }
            else{
                "Omada Url maintained: {0}" -f $Script:AppConfig.BaseUrl | Write-LogOutput -LogType DEBUG
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
