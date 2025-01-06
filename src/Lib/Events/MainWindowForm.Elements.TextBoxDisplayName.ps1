# $Script:MainWindowForm.Elements.TextBoxDisplayName.Add_Leave({
#         $_ | Show-EventInfo
#         try {
#
#             if ($Script:RunTimeData.CurrentSqlQuery.DisplayName.Split(" - ")[1] -eq $Script:MainWindowForm.Elements.TextBoxDisplayName.Text) {
#                 "DisplayName not changed" | Write-LogOutput -LogType DEBUG
#                 return
#             }
#             $QueryExists = $true
#             if ($Script:MainWindowForm.Elements.TextBoxDisplayName.Text -notin $Script:RunTimeData.QueryListCache.QueryList.Values) {
#                 "DisplayName not in cache" | Write-LogOutput -LogType DEBUG
#                 $QueryExists = $false
#             }
#             if (!$QueryExists) {
#                 $Script:RunTimeData.RestMethodParam.Uri = '{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING?$filter=Deleted ne true and NAME eq ''{1}''' -f $Script:AppConfig.BaseUrl, $Script:MainWindowForm.Elements.TextBoxDisplayName.Text
#                 "Validate if query with this name exists in Omada using queryUrl: {0}" -f $Script:RunTimeData.RestMethodParam.Uri | Write-LogOutput -LogType DEBUG
#                 $Script:RunTimeData.RestMethodParam.Body = $Null
#                 $Script:RunTimeData.RestMethodParam.Method = "GET"
#                 $Result = Invoke-OmadaPSWebRequestWrapper
#                 if (($Result.Value | Measure-Object).Count -le 0) {
#                     $QueryExists = $false
#                 }
#                 else {
#                     $QueryExists = $true
#                 }
#             }
#             if ($QueryExists) {
#                 $Script:MainWindowForm.Elements.ButtonNewQuery.Content = "Delete"
#             }
#             else {
#                 $Script:MainWindowForm.Elements.ButtonNewQuery.Content = "New"
#             }
#         }
#         catch {
#             $_.Exception.Message | Write-LogOutput -LogType ERROR
#         }
#     })

# $Script:MainWindowForm.Elements.TextBoxDisplayName.Add_TextChanged({
#         $_ | Show-EventInfo -LogType VERBOSE2
#         try {

#             if ($Script:RunTimeData.CurrentSqlQuery.DisplayName.Split(" - ")[1] -eq $Script:MainWindowForm.Elements.TextBoxDisplayName.Text) {
#                 $Script:TextboxDisplayNameChanged = $true
#             }
#             else {
#                 $Script:TextboxDisplayNameChanged = $false
#             }
#         }
#         catch {
#             $_.Exception.Message | Write-LogOutput -LogType ERROR
#         }
#     })
