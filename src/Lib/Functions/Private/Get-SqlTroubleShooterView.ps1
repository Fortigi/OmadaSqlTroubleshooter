function Get-SqlTroubleShooterView {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        $ViewResult = Get-OmadaGetPagingDataObject -SearchString "SQL Troubleshooting" -DataType "Views" -DataTypeArgs @{OwnerShipType = "Both" }
        $View = $null
        if ($null -ne $ViewResult -and $ViewResult.d.Records -gt 0) {
            $View = $ViewResult.d.Rows | Where-Object { $_.Name -eq "SQL Troubleshooting" }
        }
        $Private:Result = $null
        if ($null -ne $View) {
            $DataTypeArgs = [ordered]@{
                viewId          = ("{0}" -f $View.Id)
                pageQueryString = ("{0}/dataobjlst.aspx?view={1}" -f $Script:AppConfig.BaseUrl, $View.Id)
                readOnlyMode    = $false
                countRows       = $false
            }

            $Private:Result = Get-OmadaGetPagingDataObject -DataType "DataObjects" -DataTypeArgs $DataTypeArgs
            $Private:Result = $Private:Result.d.Rows
        }
        return $Private:Result

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
