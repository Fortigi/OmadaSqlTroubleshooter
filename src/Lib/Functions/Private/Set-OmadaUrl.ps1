function Set-OmadaUrl {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        if (![string]::IsNullOrWhiteSpace($Script:MainWindowForm.Elements.TextBoxURL.Text)) {

            $Uri = $null
            try {
                $Uri = [System.Uri]::new($Script:MainWindowForm.Elements.TextBoxURL.Text.Trim())
            }
            catch {}

            if ($null -eq $Uri) {
                if ($Script:MainWindowForm.Elements.TextBoxURL.Text -notlike "http*") {
                    if ($Script:MainWindowForm.Elements.TextBoxURL.Text -notlike "*.*" -and $Script:MainWindowForm.Elements.TextBoxURL.Text -notlike "*.omada.cloud") {
                        $Script:MainWindowForm.Elements.TextBoxURL | Set-TextBlockText -Text "https://$($Script:MainWindowForm.Elements.TextBoxURL.Text).omada.cloud"
                    }
                    else {
                        $Script:MainWindowForm.Elements.TextBoxURL | Set-TextBlockText -Text "https://$($Script:MainWindowForm.Elements.TextBoxURL.Text)"
                    }
                }
            }
            elseif ($Uri.Scheme -ne 'http' -and $Uri.Scheme -ne 'https') {
                "Input Url {0} is not valid." -f $Script:MainWindowForm.Elements.TextBoxURL.Text.Trim() | Write-LogOutput -LogType ERROR
            }

            $Uri = [System.Uri]::new($Script:MainWindowForm.Elements.TextBoxURL.Text.Trim())

            if ($Uri.IsAbsoluteUri -and ($Uri.Scheme -eq 'http' -or $Uri.Scheme -eq 'https')) {
                ("Input Url {0} is valid." -f $Uri.IsAbsoluteUri) | Write-LogOutput -LogType DEBUG
            }
            else {
                "Input Url {0} is not valid." -f $Script:MainWindowForm.Elements.TextBoxURL.Text.Trim() | Write-LogOutput -LogType ERROR
            }

            $DnsResult = $null
            try {
                $DnsResult = Resolve-DnsName -Name $Uri.Host -QuickTimeout -ErrorAction SilentlyContinue
            }
            catch {}
            if (($DnsResult | Measure-Object).Count -le 0) {
                "DNS resolution for {0} failed! Check the tenant url." -f $Uri.Host | Write-LogOutput -LogType ERROR
            }

            $Uri.AbsoluteUri.TrimEnd("/") | Set-ConfigProperty -Property "BaseUrl"

            if ($Script:CurrentUrl -ne $Script:AppConfig.BaseUrl) {
                "Omada Url set to: {0}" -f $Script:AppConfig.BaseUrl | Write-LogOutput -LogType DEBUG
                $Script:CurrentUrl = $Script:AppConfig.BaseUrl
                Set-SqlConnectionState -Status $false
                $Script:RunTimeData.RestMethodParam.ForceAuthentication = $true
            }
            elseif ([string]::IsNullOrEmpty($Script:AppConfig.BaseUrl)) {
                "Omada Url is empty!" | Write-LogOutput -LogType DEBUG
                Set-SqlConnectionState -Status $false
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
        $Script:MainWindowForm.Elements.TextBoxURL | Set-TextBlockText -Text $null
        $null | Set-ConfigProperty -Property "BaseUrl"
        Set-SqlConnectionState -Status $false
        $_
    }
}
