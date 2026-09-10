function New-OmadaQueryRequest {
    <#
    .SYNOPSIS
    Build the method, URI and body for one Omada request in the execute path, from plain values.

    .DESCRIPTION
    Every URL and body shape the execute path uses, in one place, expressed as a pure function of a
    context hashtable: no $Script: reads, no logging, no network. That makes it usable from two
    places that must never disagree - the UI-thread functions (Save-Query,
    New-TemporarySqlQueryObject, Remove-SqlQueryObject, Invoke-ExecuteQuery) and
    Invoke-OmadaExecutePipeline, which runs the same sequence inside a background worker (issue #40,
    C1-5).

    Written as one function with a -Kind rather than six small ones so that the request shapes sit
    side by side: they share a base URL, an entity path and a body convention, and a change to one is
    usually a change to its neighbours.

    Being pure is also what makes these testable at all. Before this, "which URL does saving a query
    use, and when is the body empty?" could only be answered by running the app against a tenant.

    .PARAMETER Kind
    Which request to build:

      SaveExistingQuery  PUT the current query. Returns $null when nothing changed - the caller must
                         treat that as "no request needed", exactly as Save-Query's "No changes
                         detected!" branch always has.
      ExecuteQuery       POST GetPagingData for a target query id.
      TempQueryProbe     GET the TMP_<guid> object by name, including deleted ones.
      TempQueryUndelete  POST UndeleteDataObject for a soft-deleted temporary object.
      TempQueryUpsert    PUT (reuse) or POST (create) the temporary object carrying the selection.
      DeleteQuery        DELETE a query object by id.

    .PARAMETER Context
    Plain values gathered on the UI thread. Keys used, by Kind:
      BaseUrl              all
      QueryDoId            SaveExistingQuery
      QueryText            SaveExistingQuery
      CurrentQueryText     SaveExistingQuery  (the text last known to be saved)
      SavedQueryText       SaveExistingQuery  (C_QUERY from the freshly fetched object)
      DisplayName          SaveExistingQuery  (what the Display name box holds now)
      CurrentDisplayName   SaveExistingQuery  (the name last known to be saved)
      DataConnectionDoId   SaveExistingQuery, TempQueryUpsert
      TargetQueryDoId      ExecuteQuery
      TempName             TempQueryProbe, TempQueryUpsert
      TempQueryDoId        TempQueryUndelete, TempQueryUpsert (reuse), DeleteQuery
      SelectionText        TempQueryUpsert

    .OUTPUTS
    Hashtable @{ Method; Uri; Body }, or $null when no request is needed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("SaveExistingQuery", "ExecuteQuery", "TempQueryProbe", "TempQueryUndelete", "TempQueryUpsert", "DeleteQuery")]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $Private:BaseUrl = [string]$Context.BaseUrl
    $Private:EntityUrl = "{0}/odata/dataobjects/C_P_SQLTROUBLESHOOTING" -f $Private:BaseUrl

    switch ($Kind) {

        "SaveExistingQuery" {
            # The diff rules, preserved exactly as Save-Query has always applied them: the query text
            # is sent when it differs from either what this session last saved OR what the server
            # actually holds, and the name is sent when the Display name box no longer matches the
            # name last saved. An empty body means nothing changed.
            $Private:Body = @{}

            if ($Context.QueryText -ne $Context.CurrentQueryText -or $Context.QueryText -ne $Context.SavedQueryText) {
                $Private:Body.Add("C_QUERY", $Context.QueryText)
                if (![string]::IsNullOrWhiteSpace($Context.DataConnectionDoId)) {
                    $Private:Body.Add("C_SQLTROUBLESHOOTING_DATACONNECTION", @{ Id = $Context.DataConnectionDoId })
                }
            }

            if ($Context.CurrentDisplayName -ne $Context.DisplayName) {
                $Private:Body.Add("NAME", $Context.DisplayName)
            }

            if (($Private:Body.Keys | Measure-Object).Count -le 0) {
                return $null
            }

            return @{
                Method = "PUT"
                Uri    = "{0}({1})" -f $Private:EntityUrl, $Context.QueryDoId
                Body   = $Private:Body
            }
        }

        "ExecuteQuery" {
            return @{
                Method = "POST"
                Uri    = "{0}/webservice/jQGridPopulationWebService.asmx/GetPagingData" -f $Private:BaseUrl
                Body   = @{
                    "dataType"     = "SqlDataProducer"
                    "dataTypeArgs" = @{
                        "targetId" = $Context.TargetQueryDoId
                    }
                    "page"         = 1
                    "rows"         = 100000
                    "sidx"         = $null
                    "sord"         = "asc"
                    "_search"      = $false
                    "searchField"  = $null
                    "searchString" = $null
                    "filters"      = $null
                    "searchOper"   = $null
                }
            }
        }

        "TempQueryProbe" {
            # DeletedStatus=Both on purpose: the temporary object is soft-deleted after every run, so
            # the one being looked for is normally in the deleted set.
            return @{
                Method = "GET"
                Uri    = "{0}?DeletedStatus=Both&`$filter=NAME eq '{1}'" -f $Private:EntityUrl, $Context.TempName
                Body   = $null
            }
        }

        "TempQueryUndelete" {
            return @{
                Method = "POST"
                Uri    = "{0}/WebService/DataObjectWebService.asmx/UndeleteDataObject" -f $Private:BaseUrl
                # Pre-serialized, as this endpoint has always been called: it is an ASMX method that
                # wants a JSON string rather than the object the OData endpoints take.
                Body   = (@{ id = $Context.TempQueryDoId } | ConvertTo-Json)
            }
        }

        "TempQueryUpsert" {
            $Private:Body = @{
                "NAME"    = $Context.TempName
                "C_QUERY" = $Context.SelectionText
            }
            if (![string]::IsNullOrWhiteSpace($Context.DataConnectionDoId)) {
                $Private:Body.Add("C_SQLTROUBLESHOOTING_DATACONNECTION", @{ Id = $Context.DataConnectionDoId })
            }

            # PUT onto the recovered object when there is one, POST a new one otherwise. The name is
            # always TMP_<InstanceGuid> - never a fresh guid - so a missing temporary object is
            # recreated under the same name instead of piling up stale ones on the tenant.
            if (![string]::IsNullOrWhiteSpace($Context.TempQueryDoId)) {
                return @{
                    Method = "PUT"
                    Uri    = "{0}({1})" -f $Private:EntityUrl, $Context.TempQueryDoId
                    Body   = $Private:Body
                }
            }

            return @{
                Method = "POST"
                Uri    = $Private:EntityUrl
                Body   = $Private:Body
            }
        }

        "DeleteQuery" {
            return @{
                Method = "DELETE"
                Uri    = "{0}({1})" -f $Private:EntityUrl, $Context.TempQueryDoId
                Body   = $null
            }
        }
    }
}
