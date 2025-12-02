function Initialize-FormEvents {
    [CmdletBinding()]
    param (
        [string]$FormName
    )

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

    Get-ChildItem -Path (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "Lib\Events") -Filter *.ps1 | Where-Object { $_.Name -like "$($FormName).*" -and $_.Name -notlike "_*.ps1" } | ForEach-Object {

        "Loading event {0}" -f $_.Name | Write-LogOutput -LogType DEBUG
        try {

            . $_.FullName
        }
        catch {
            if ($_.Exception.Response.StatusCode -eq "NotFound") {
                "SQL Troubleshooting Object not found or OData endpoint for SQL Troubleshooting is not found. Is it enable for OData? Please check the data object type properties!" | Write-LogOutput -LogType ERROR -ErrorObject $_
            }
            else {
                $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
            }
        }
    }
}
