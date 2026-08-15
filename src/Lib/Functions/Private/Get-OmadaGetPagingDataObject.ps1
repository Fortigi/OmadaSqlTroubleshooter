function Get-OmadaGetPagingDataObject {
    [CmdLetBinding()]
    param(
        [parameter(Mandatory = $true, Position = 0)]
        [string]$DataType,
        [parameter(Mandatory = $true, Position = 1)]
        [hashtable]$DataTypeArgs,
        [parameter(Mandatory = $false, Position = 3)]
        [string]$SearchString = $null,
        [parameter(Mandatory = $false, Position = 4)]
        [int]$Rows = 1000
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
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
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
