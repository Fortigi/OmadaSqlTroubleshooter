function Update-SqlSchemaWindow {

    try {
        if ($null -ne $Script:TreeViewSqlSchema) {
            $Script:TreeViewSqlSchema.Dispatcher.Invoke({
                    $null
                })
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
