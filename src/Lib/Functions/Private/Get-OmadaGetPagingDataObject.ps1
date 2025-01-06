function Get-OmadaGetPagingDataObject {
    PARAM(
        [parameter(Mandatory = $True, Position = 0)]
        [string]$DataType,
        [parameter(Mandatory = $True, Position = 1)]
        [hashtable]$DataTypeArgs,
        [parameter(Mandatory = $False, Position = 3)]
        [string]$SearchString = $null,
        [parameter(Mandatory = $false, Position = 4)]
        [int]$Rows = 1000
    )

    try {

        $Script:RunTimeData.RestMethodParam.Body = [ordered]@{
            _search      = $false
            nd           = 1732546553116
            rows         = $Rows
            page         = 1
            sidx         = [string]::IsNullOrWhiteSpace($SearchString) ? $null : "name"
            sord         = "asc"
            searchField  = $null
            searchString = [string]::IsNullOrWhiteSpace($SearchString) ? $null : $SearchString
            searchOper   = $null
            filters      = $null
            dataType     = $DataType
            dataTypeArgs = $DataTypeArgs
        }

        $Script:RunTimeData.RestMethodParam.Uri = '{0}/WebService/JQGridPopulationWebService.asmx/GetPagingData' -f $Script:AppConfig.BaseUrl
        $Script:RunTimeData.RestMethodParam.Method = "POST"

        return Invoke-OmadaPSWebRequestWrapper

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
