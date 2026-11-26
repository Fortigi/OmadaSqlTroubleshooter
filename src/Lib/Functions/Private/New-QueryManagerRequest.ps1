function New-QueryManagerRequest {
    <#
    .SYNOPSIS
    Build the method, URI and body for the query manager's own requests, from plain values.

    .DESCRIPTION
    The query manager's counterpart of New-OmadaQueryRequest: pure (no $Script: reads, no logging, no
    network), so every request it sends is asserted in tests rather than found out on a tenant. Kept
    apart from New-OmadaQueryRequest because that one is dot-sourced into the background execute
    worker, which needs none of these.

    .PARAMETER Kind
      QueryObjectList  GET every query object, deleted ones included (DeletedStatus=Both, as the
                       temporary query probe asks), ordered by display name. The query manager's view
                       chooses which it shows (Test-QueryManagerView).
      QueryObject      GET one query object by id, with its text and data connection.
      CreateQuery      POST a new query object: NAME, C_QUERY and, when given, the data connection.
      QueryHistory     POST GetPagingData for one query object's change history, newest first - the
                       request the history window has always made, for any query.
      RestoreQuery     POST UndeleteDataObject for a deleted query object - the call the application
                       already makes to recover its own temporary object (New-OmadaQueryRequest
                       TempQueryUndelete).

    .PARAMETER Context
    Plain values. Keys used, by Kind:
      BaseUrl              all
      QueryDoId            QueryObject, QueryHistory, RestoreQuery
      QueryName            CreateQuery
      QueryText            CreateQuery
      DataConnectionDoId   CreateQuery

    .OUTPUTS
    Hashtable @{ Method; Uri; Body }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("QueryObjectList", "QueryObject", "CreateQuery", "QueryHistory", "RestoreQuery")]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $Private:BaseUrl = [string]$Context.BaseUrl
    $Private:EntityUrl = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING" -f $Private:BaseUrl

    switch ($Kind) {

        "QueryObjectList" {
            return @{
                Method = "GET"
                Uri    = "{0}?DeletedStatus=Both&`$orderby=DisplayName,NAME" -f $Private:EntityUrl
                Body   = $null
            }
        }

        "QueryObject" {
            return @{
                Method = "GET"
                Uri    = "{0}({1})" -f $Private:EntityUrl, $Context.QueryDoId
                Body   = $null
            }
        }

        "CreateQuery" {
            $Private:Body = @{
                "NAME"    = $Context.QueryName
                "C_QUERY" = $Context.QueryText
            }
            if (![string]::IsNullOrWhiteSpace($Context.DataConnectionDoId)) {
                $Private:Body.Add("C_SQLTROUBLESHOOTING_DATACONNECTION", @{ Id = $Context.DataConnectionDoId })
            }
            return @{
                Method = "POST"
                Uri    = $Private:EntityUrl
                Body   = $Private:Body
            }
        }

        "RestoreQuery" {
            return @{
                Method = "POST"
                Uri    = "{0}/WebService/DataObjectWebService.asmx/UndeleteDataObject" -f $Private:BaseUrl
                # Pre-serialized, as TempQueryUndelete sends it: an ASMX method that wants a JSON string.
                Body   = (@{ id = $Context.QueryDoId } | ConvertTo-Json)
            }
        }

        "QueryHistory" {
            # The same request the history window has always made (Get-SqlHistory), for any query.
            return @{
                Method = "POST"
                Uri    = "{0}/webservice/jQGridPopulationWebService.asmx/GetPagingData" -f $Private:BaseUrl
                Body   = @{
                    "dataType"     = "DataObjectHistory"
                    "dataTypeArgs" = @{
                        "dataObjectId" = $Context.QueryDoId
                        "propertyId"   = 0
                        "userId"       = 0
                    }
                    "page"         = 1
                    "rows"         = 100000
                    "sidx"         = "when"
                    "sord"         = "desc"
                    "_search"      = $false
                    "searchField"  = $null
                    "searchString" = $null
                    "filters"      = $null
                    "searchOper"   = $null
                }
            }
        }
    }
}
