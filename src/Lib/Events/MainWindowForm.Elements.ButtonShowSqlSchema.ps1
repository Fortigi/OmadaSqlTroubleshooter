$Script:MainWindowForm.Elements.ButtonShowSqlSchema.Add_Click({
    $_ | Show-EventInfo
    if (Test-SqlSchemaWindowOpen) {
        "Hide log" | Write-LogOutput -LogType DEBUG
        $Script:SqlSchemaWindowForm.Definition.Close()
    }
    else {
        "Show schema" | Write-LogOutput -LogType DEBUG
        Open-SqlSchemaWindow
    }
})
