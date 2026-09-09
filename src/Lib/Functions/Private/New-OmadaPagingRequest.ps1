function New-OmadaPagingRequest {
    <#
    .SYNOPSIS
    Build the method, URI and body for one jqGrid GetPagingData request, from plain values.

    .DESCRIPTION
    Issue #90, slice A. The same idea as New-OmadaQueryRequest, for the other endpoint this
    application talks to: a pure function of a context hashtable - no $Script: reads, no logging, no
    network - so that the UI-thread caller (Get-OmadaGetPagingDataObject) and the background worker
    (Invoke-OmadaViewLookupPipeline) build byte-identical requests instead of two copies drifting
    apart.

    That mattered immediately. The body below carries `nd = 1732546553116`, a cache-busting
    timestamp that jqGrid normally regenerates per request and which this application has always
    sent as a constant. Copying it into a second definition is exactly how a value like that
    silently becomes two different constants.

    .PARAMETER DataType
    The jqGrid data type - "Views" or "DataObjects" for the lookups this application makes.

    .PARAMETER DataTypeArgs
    The type-specific arguments, passed through unchanged.

    .PARAMETER SearchString
    Optional. When supplied, the request searches the "name" column for it; when not, no sort index
    and no search string are sent. Preserved exactly as Get-OmadaGetPagingDataObject has always
    built it, because sidx and searchString move together.

    .PARAMETER Rows
    Page size. Defaults to the 1000 this application has always requested.

    .PARAMETER BaseUrl
    The tenant base URL. Passed in rather than read from $Script:AppConfig, which does not exist in a
    worker runspace.

    .OUTPUTS
    Hashtable @{ Method; Uri; Body }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataType,

        [Parameter(Mandatory = $true)]
        [hashtable]$DataTypeArgs,

        [string]$SearchString = $null,

        [int]$Rows = 1000,

        [Parameter(Mandatory = $true)]
        [string]$BaseUrl
    )

    $Private:HasSearch = -not [string]::IsNullOrWhiteSpace($SearchString)

    return @{
        Method = "POST"
        Uri    = "{0}/WebService/JQGridPopulationWebService.asmx/GetPagingData" -f $BaseUrl
        Body   = [ordered]@{
            _search      = $false
            nd           = 1732546553116
            rows         = $Rows
            page         = 1
            sidx         = $(if ($Private:HasSearch) { "name" } else { $null })
            sord         = "asc"
            searchField  = $null
            searchString = $(if ($Private:HasSearch) { $SearchString } else { $null })
            searchOper   = $null
            filters      = $null
            dataType     = $DataType
            dataTypeArgs = $DataTypeArgs
        }
    }
}
