function Set-SqlQueryFunctionState {
    [CmdLetBinding()]
    param(
        [bool]$Status = $true
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))


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
            # DataGridQueryResult is deliberately absent. Issue #151 retired that name when the single
            # result grid became one grid per statement, so this list would resolve it to $null - and
            # the loops below call .GetType().Name on every entry, which throws on $null. That would
            # have taken down every connect and disconnect.
            #
            # Clearing the results is now an explicit Clear-TabQueryResult call in the disable branch,
            # which also clears the list on the tab session rather than only the control bound to it.
        }

        if ($Status) {
            $ElementList.Keys | Where-Object { $ElementList.$_.AllowedStatusChange -ne "Disable" } | ForEach-Object {
                $Item = $_
                switch ($Script:MainForm.Elements.$Item.GetType().Name) {
                    "DataGrid" {}
                    default {

                        if ($null -eq $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem.Content -and $Item -in ("ButtonShowSqlSchema", "ButtonSaveOutputFile", "ButtonShowOutput", "ButtonOpenOutputFile", "ButtonSaveQuery", "ButtonHistory", "ButtonRefreshQueries", "ButtonExecuteQuery")) {
                            continue
                        }
                        $Script:MainForm.Elements.$Item.IsEnabled = $true
                    }
                }
            }
        }
        else {
            # What the DataGridQueryResult entry used to achieve through the switch below: a tab that
            # disconnects must not keep showing results it can no longer refresh. Both halves are
            # cleared - the per-statement list on the tab session and the pane bound to it - because
            # clearing only the control would leave the session believing in results that are no
            # longer on screen.
            Clear-TabQueryResult

            $ElementList.Keys | Where-Object { $ElementList.$_.AllowedStatusChange -ne "Enable" } | ForEach-Object {
                $Item = $_

                switch ($Script:MainForm.Elements.$Item.GetType().Name) {
                    "ComboBox" {
                        $Script:MainForm.Elements.$Item.Items.Clear()
                        $Script:MainForm.Elements.$Item.IsEnabled = $false
                    }
                    "TextBox" {
                        $Script:MainForm.Elements.$Item.Text = $null
                        $Script:MainForm.Elements.$Item.IsEnabled = $false
                    }
                    "DataGrid" {
                        $Script:MainForm.Elements.$Item.ItemsSource = $null
                    }
                    default {
                        $Script:MainForm.Elements.$Item.IsEnabled = $false
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
