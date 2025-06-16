function Get-OmadaGetPagingDataObject {
    [CmdLetBinding()]
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
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName), $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        $Script:RunTimeData.RestMethodParam.Body = [ordered]@{
            _search      = $false
            nd           = 1732546553116
            rows         = $Rows
            page         = 1
            sidx         = $(if ([string]::IsNullOrWhiteSpace($SearchString)) { $null }else { "name" })
            sord         = "asc"
            searchField  = $null
            searchString = $(if ([string]::IsNullOrWhiteSpace($SearchString)) { $null }else { $SearchString })
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
