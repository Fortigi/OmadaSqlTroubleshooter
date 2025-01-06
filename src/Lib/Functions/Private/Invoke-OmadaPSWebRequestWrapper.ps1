function Invoke-OmadaPSWebRequestWrapper {
    try {
        try {
            $Private:Parameters = $Script:RunTimeData.RestMethodParam
            $Private:Parameters.AuthenticationType = $($Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content)
            if ($Null -eq $Private:Parameters.Body) {
                if ($Private:Parameters.ContainsKey("Body")) {
                    $Private:Parameters.Remove("Body")
                }
            }
            else {
                if (!$Private:Parameters.ContainsKey("Body")) {
                    $Private:Parameters.Add("Body", $Null)
                }

                $Private:Parameters.Body = $Private:Parameters.Body | ConvertTo-Json
            }
            "Parameters: {0}" -f ($Private:Parameters | ConvertTo-Json -Depth 15) | Write-LogOutput -LogType VERBOSE
            $Private:Result = Invoke-OmadaRestMethod @Parameters
            if($null -ne $Script:MainWindowForm -and $null -ne $Script:MainWindowForm.Definitions -and $Script:MainWindowForm.Definitions.IsVisible){
                $Script:MainWindowForm.Definitions.TextBlockConnectionStatus | Set-TextBlockText -Text "Connected"
            }
            "Result: {0}" -f ($Private:Result | ConvertTo-Json -Depth 15) | Write-LogOutput -LogType VERBOSE
            return $Private:Result
        }
        catch {
            if (![string]::IsNullOrWhiteSpace($_.ErrorDetails?.Message) -and $_.ErrorDetails.Message -like "*Resource not found for the segment 'C_P_SQLTROUBLESHOOTING'*") {
                $Message = "OData Endpoint for SQL Troubleshooting not enabled at tenant {0}.`n`r`n`rError returned by Omada:`n`r`n`r{1}" -f [system.uri]::New($Script:AppConfig.BaseUrl).Host, $_.ErrorDetails.Message
                $Message | Write-LogOutput -LogType ERROR
                if($null -ne $Script:MainWindowForm -and $null -ne $Script:MainWindowForm.Definitions -and $Script:MainWindowForm.Definitions.IsVisible){
                    $Script:MainWindowForm.Definitions.TextBlockConnectionStatus | Set-TextBlockText -Text "Disconnected"
                }
                else{
                    Throw $_
                }
            }
            else{
                Throw $_
            }
        }
    }
    catch {
        Throw $_
    }
}
