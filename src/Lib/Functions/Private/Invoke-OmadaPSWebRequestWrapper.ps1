function Invoke-OmadaPSWebRequestWrapper {
    [CmdLetBinding()]
    param()

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
    try {
        if (!$Script:RunTimeData.SkipRetryRequest) {
            $Private:Parameters = $Script:RunTimeData.RestMethodParam
            $Private:Parameters.AuthenticationType = $($Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content)
            $Private:Parameters.UseWebView2 = $Private:Parameters.AuthenticationType -eq "Browser" ? $($Script:RunTimeConfig.UseWebView2Auth) : $false
            if ($null -eq $Private:Parameters.Body) {
                if ($Private:Parameters.ContainsKey("Body")) {
                    $Private:Parameters.Remove("Body")
                }
            }
            else {
                if (!$Private:Parameters.ContainsKey("Body")) {
                    $Private:Parameters.Add("Body", $null)
                }

                #$Private:Parameters.Body = $Private:Parameters.Body | ConvertTo-Json
            }
            "Parameters: {0}" -f ($Private:Parameters | ConvertTo-Json -Depth 15) | Write-LogOutput -LogType VERBOSE
            $Private:Result = Invoke-OmadaRestMethod @Parameters
            if ($null -ne $Script:MainWindowForm -and $null -ne $Script:MainWindowForm.Definitions -and $Script:MainWindowForm.Definitions.IsVisible) {
                $Script:MainWindowForm.Definitions.TextBlockStatusBarConnectionStatus | Set-TextBlockText -Text "Connected"
            }
            "Result: {0}" -f ($Private:Result | ConvertTo-Json -Depth 15) | Write-LogOutput -LogType VERBOSE
            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false
            return $Private:Result
        }
        else {
            return $null
        }
    }
    catch {
        if (![string]::IsNullOrWhiteSpace($_.ErrorDetails?.Message) -and $_.ErrorDetails.Message -like "*Resource not found for the segment 'C_P_SQLTROUBLESHOOTING'*") {
            $Message = "OData Endpoint for SQL Troubleshooting not enabled at tenant {0}.`n`r`n`rError returned by Omada:`n`r`n`r{1}" -f [system.uri]::New($Script:AppConfig.BaseUrl).Host, $_.ErrorDetails.Message
            if ($null -ne $Script:MainWindowForm -and $null -ne $Script:MainWindowForm.Definitions -and $Script:MainWindowForm.Definitions.IsVisible) {
                $Script:MainWindowForm.Elements.TextBlockStatusBarConnectionStatus | Set-TextBlockText -Text "Disconnected"
                $Script:MainWindowForm.Elements.TextBlockStatusBarDatabaseName | Set-TextBlockText -Text "-"
                $Script:MainWindowForm.Elements.TextBlockStatusBarUrl | Set-TextBlockText -Text "-"
                $Script:MainWindowForm.Elements.TextBlockStatusBarQueryTime | Set-TextBlockText -Text "00:00:00.0000000"
            }
            $Message | Write-Error -ErrorAction Stop -TargetObject $_
            $Script:RunTimeData.SkipRetryRequest = $true
        }
        elseif ($null -ne $_.Exception?.Response?.StatusCode -and $_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::Unauthorized) {
            $Message = "Access denied to {0}, message:`n`r{1}" -f [system.uri]::New($Script:AppConfig.BaseUrl).Host, $_.ErrorDetails.Message
            Set-SqlConnectionState -Status $false
            $Message | Write-Error -ErrorAction Stop -TargetObject $_
            $Script:RunTimeData.SkipRetryRequest = $true
        }
        else {
            # $Message = "Error occurred:`n`r{1}" -f [system.uri]::New($Script:AppConfig.BaseUrl).Host, $_.ErrorDetails.Message
            # $Message | Write-Error -ErrorAction Stop -TargetObject $_
            $_
        }
    }
}
