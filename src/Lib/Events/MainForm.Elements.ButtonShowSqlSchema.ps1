$Script:MainForm.Elements.ButtonShowSqlSchema.Add_Click({
        try {
            $_ | Show-EventInfo
            if (Test-SqlSchemaFormIsVisible) {
                "Hide log" | Write-LogOutput -LogType DEBUG
                $Script:SqlSchemaForm.Definition.Close()
            }
            else {
                "Show schema" | Write-LogOutput -LogType DEBUG
                Open-SqlSchemaForm
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
