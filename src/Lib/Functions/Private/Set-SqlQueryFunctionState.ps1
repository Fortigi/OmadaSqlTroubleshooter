function Set-SqlQueryFunctionState {
    [CmdLetBinding()]
    param(
        [bool]$Status = $true
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))


        $ElementList = @{
            "ComboBoxSelectDataConnection" = @{
                AllowedStatusChange = "Both"
            }
            "ComboBoxSelectQuery"          = @{
                AllowedStatusChange = "Both"
            }
            "CheckboxMyCreatedQueries"     = @{
                AllowedStatusChange = "Both"
            }
            "CheckboxMyUpdatedQueries"     = @{
                AllowedStatusChange = "Both"
            }
            "ButtonRefreshQueries"         = @{
                AllowedStatusChange = "Both"
            }
            "ButtonNewQuery"               = @{
                AllowedStatusChange = "Both"
            }
            "TextBoxDisplayName"           = @{
                AllowedStatusChange = "Both"
            }
            "ButtonShowSqlSchema"          = @{
                AllowedStatusChange = "Disable"
            }
            "ButtonShowHistory"            = @{
                AllowedStatusChange = "Both"
            }
            "ButtonSaveOutputFile"         = @{
                AllowedStatusChange = "Disable"
            }
            "ButtonShowOutput"             = @{
                AllowedStatusChange = "Disable"
            }
            "ButtonExecuteQuery"           = @{
                AllowedStatusChange = "Both"
            }
            "ButtonOpenOutputFile"         = @{
                AllowedStatusChange = "Disable"
            }
            "ButtonSaveQuery"              = @{
                AllowedStatusChange = "Disable"
            }
            "DataGridQueryResult"          = @{
                AllowedStatusChange = "Disable"
            }
        }

        if ($Status) {
            $ElementList.Keys | Where-Object { $ElementList.$_.AllowedStatusChange -ne "Disable" } | ForEach-Object {
                $Item = $_
                switch ($Script:MainFormForm.Elements.$Item.GetType().Name) {
                    "DataGrid" {}
                    default {

                        if ($null -eq $Script:MainFormForm.Elements.ComboBoxSelectQuery.SelectedItem.Content -and $Item -in ("ButtonShowSqlSchema", "ButtonSaveOutputFile", "ButtonShowOutput", "ButtonOpenOutputFile", "ButtonSaveQuery", "ButtonHistory", "ButtonRefreshQueries", "ButtonExecuteQuery")) {
                            continue
                        }
                        $Script:MainFormForm.Elements.$Item.IsEnabled = $true
                    }
                }
            }
        }
        else {
            $ElementList.Keys | Where-Object { $ElementList.$_.AllowedStatusChange -ne "Enable" } | ForEach-Object {
                $Item = $_

                switch ($Script:MainFormForm.Elements.$Item.GetType().Name) {
                    "ComboBox" {
                        $Script:MainFormForm.Elements.$Item.Items.Clear()
                        $Script:MainFormForm.Elements.$Item.IsEnabled = $false
                    }
                    "TextBox" {
                        $Script:MainFormForm.Elements.$Item.Text = $null
                        $Script:MainFormForm.Elements.$Item.IsEnabled = $false
                    }
                    "DataGrid" {
                        $Script:MainFormForm.Elements.$Item.ItemsSource = $null
                    }
                    default {
                        $Script:MainFormForm.Elements.$Item.IsEnabled = $false
                    }
                }

                if (Test-SqlSchemaFormIsVisible) {
                    $Script:SqlSchemaForm.Definition.Close()
                }
                if (Test-SqlHistoryFormOpen) {
                    $Script:SqlHistoryForm.Definition.Close()
                }
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
