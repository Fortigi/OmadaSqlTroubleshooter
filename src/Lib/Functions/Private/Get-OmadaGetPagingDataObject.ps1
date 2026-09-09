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
        # Built by New-OmadaPagingRequest rather than inline, so this request and the one
        # Invoke-OmadaViewLookupPipeline issues from a worker are the same request (issue #90). The
        # body carries a constant cache-busting `nd`, which is precisely the kind of value that
        # becomes two different constants once it exists in two places.
        $Private:Request = New-OmadaPagingRequest -DataType $DataType -DataTypeArgs $DataTypeArgs -SearchString $SearchString -Rows $Rows -BaseUrl $Script:AppConfig.BaseUrl

        $Script:RunTimeData.RestMethodParam.Body = $Private:Request.Body
        $Script:RunTimeData.RestMethodParam.Uri = $Private:Request.Uri
        $Script:RunTimeData.RestMethodParam.Method = $Private:Request.Method

        return Invoke-OmadaPSWebRequestWrapper

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
