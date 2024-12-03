function Invoke-OmadaPSWebRequestWrapper {
    try {
        try {
            $InvokeOmadaRestMethodParam.Uri = $QueryUrl
            $InvokeOmadaRestMethodParam.Method = $Method
            $InvokeOmadaRestMethodParam.AuthenticationType = $($Script:MainWindowForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content)
            if ($Null -eq $Body) {
                if ($InvokeOmadaRestMethodParam.ContainsKey("Body")) {
                    $InvokeOmadaRestMethodParam.Remove("Body")
                }
            }
            else {
                if (!$InvokeOmadaRestMethodParam.ContainsKey("Body")) {
                    $InvokeOmadaRestMethodParam.Add("Body", $Null)
                }

                $InvokeOmadaRestMethodParam.Body = $Body | ConvertTo-Json
            }
            $Result = Invoke-OmadaRestMethod @Script:InvokeOmadaRestMethodParam
            "Result: {0}" -f ($Result | ConvertTo-Json -Depth 15) | Write-LogOutput -LogType VERBOSE
            return $Result
        }
        catch {
            if (![string]::IsNullOrWhiteSpace($_.ErrorDetails?.Message)) {

                if ($_.ErrorDetails.Message -like "*Resource not found for the segment 'C_P_SQLTROUBLESHOOTING'*") {
                    $Message = "OData Endpoint for SQL Troubleshooting not enabled at tenant {0}.`n`r`n`rError returned by Omada:`n`r`n`r{1}" -f [system.uri]::New($Script:AppConfig.BaseUrl).Host, $_.ErrorDetails.Message
                }
                else {
                    $Message = $_.ErrorDetails.Message
                }
                try {
                    $MessageObject = $Message | ConvertFrom-Json

                    $Message = (($MessageObject | Get-Member -MemberType NoteProperty).Name | ForEach-Object { "{0}: {1}" -f $_, $MessageObject.$_ }) -join "`r`n"
                }
                catch {}
            }
            else {
                $Message = $_.Exception.Message
            }
            $Message | Write-LogOutput -LogType ERROR
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
