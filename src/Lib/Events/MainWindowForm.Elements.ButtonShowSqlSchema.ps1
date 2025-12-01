$Script:MainWindowForm.Elements.ButtonShowSqlSchema.Add_Click({
        try {
            $_ | Show-EventInfo
            if (Test-SqlSchemaWindowOpen) {
                "Hide log" | Write-LogOutput -LogType DEBUG
                $Script:SqlSchemaWindowForm.Definition.Close()
            }
            else {
                "Show schema" | Write-LogOutput -LogType DEBUG
                Open-SqlSchemaWindow
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
