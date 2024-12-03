function Get-SqlTroubleShooterView {

    try {

        $ViewResult = Get-OmadaGetPagingDataObject -SearchString "SQL Troubleshooting" -DataType "Views" -DataTypeArgs @{OwnerShipType = "Both" }
        $View = $null
        if ($null -ne $ViewResult -and $ViewResult.d.Records -gt 0) {
            $View = $ViewResult.d.Rows | Where-Object { $_.Name -eq "SQL Troubleshooting" }
        }
        $Result = $null
        if ($null -ne $View) {
            $DataTypeArgs = [ordered]@{
                viewId          = ("{0}" -f $View.Id)
                pageQueryString = ("{0}/dataobjlst.aspx?view={1}" -f $Script:AppConfig.BaseUrl, $View.Id)
                readOnlyMode    = $false
                countRows       = $false
            }

            $Result = Get-OmadaGetPagingDataObject -DataType "DataObjects" -DataTypeArgs $DataTypeArgs
            $Result = $Result.d.Rows
        }
        return $Result

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
