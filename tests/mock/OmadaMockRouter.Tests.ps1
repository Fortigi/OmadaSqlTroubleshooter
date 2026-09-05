#Requires -Version 7.0
# Pure classification tests for the mock router - no server, no Windows, safe in CI.

BeforeAll {
    . (Join-Path $PSScriptRoot "OmadaMockRouter.ps1")
    $script:Base = "https://tenant.omada.cloud"
}

Describe "Get-OmadaMockRouteKey" {
    It "classifies the bare OData probe as 'probe'" {
        Get-OmadaMockRouteKey -Path "$Base/odata/dataobjects/C_P_SQLTROUBLESHOOTING" -Method "GET" | Should -Be "probe"
    }
    It "classifies the ordered query list as 'querylist'" {
        Get-OmadaMockRouteKey -Path "$Base/odata/dataobjects/C_P_SQLTROUBLESHOOTING?`$orderby=DisplayName,NAME&`$filter=Deleted ne true" -Method "GET" | Should -Be "querylist"
    }
    It "classifies a name-eq filter as 'namecheck'" {
        Get-OmadaMockRouteKey -Path "$Base/odata/dataobjects/C_P_SQLTROUBLESHOOTING?`$filter=Deleted ne true and NAME eq 'Foo'" -Method "GET" | Should -Be "namecheck"
    }
    It "classifies GET by id as 'queryobject'" {
        Get-OmadaMockRouteKey -Path "$Base/odata/dataobjects/C_P_SQLTROUBLESHOOTING(10521)" -Method "GET" | Should -Be "queryobject"
    }
    It "classifies DELETE by id as 'deletequery'" {
        Get-OmadaMockRouteKey -Path "$Base/odata/dataobjects/C_P_SQLTROUBLESHOOTING(10521)" -Method "DELETE" | Should -Be "deletequery"
    }
    It "classifies PATCH by id as 'updatequery'" {
        Get-OmadaMockRouteKey -Path "$Base/odata/dataobjects/C_P_SQLTROUBLESHOOTING(10521)" -Method "PATCH" | Should -Be "updatequery"
    }
    It "classifies POST (no parens) as 'createquery'" {
        Get-OmadaMockRouteKey -Path "$Base/odata/dataobjects/C_P_SQLTROUBLESHOOTING" -Method "POST" | Should -Be "createquery"
    }
    It "classifies GetSqlSchema as 'schema'" {
        Get-OmadaMockRouteKey -Path "$Base/webservice/SyntaxHighlighting.asmx/GetSqlSchema" -Method "POST" | Should -Be "schema"
    }
    It "classifies UndeleteDataObject as 'undelete'" {
        Get-OmadaMockRouteKey -Path "$Base/WebService/DataObjectWebService.asmx/UndeleteDataObject" -Method "POST" | Should -Be "undelete"
    }
    It "classifies the data connection dialog as 'dataconnections'" {
        Get-OmadaMockRouteKey -Path "$Base/dataobjdlg.aspx?DOID=8801" -Method "GET" | Should -Be "dataconnections"
    }

    Context "GetPagingData routes on the body dataType" {
        It "routes '<Type>' to '<Expected>' (hashtable body)" -TestCases @(
            @{ Type = "Views"; Expected = "paging.views" }
            @{ Type = "DataObjects"; Expected = "paging.dataobjects" }
            @{ Type = "SqlDataProducer"; Expected = "paging.sqldataproducer" }
            @{ Type = "DataObjectHistory"; Expected = "paging.dataobjecthistory" }
        ) {
            param($Type, $Expected)
            $Body = @{ dataType = $Type; page = 1 }
            Get-OmadaMockRouteKey -Path "$Base/webservice/jQGridPopulationWebService.asmx/GetPagingData" -Method "POST" -Body $Body | Should -Be $Expected
        }
        It "also reads the dataType from a raw JSON string body" {
            $Json = '{"dataType":"SqlDataProducer","page":1}'
            Get-OmadaMockRouteKey -Path "$Base/WebService/JQGridPopulationWebService.asmx/GetPagingData" -Method "POST" -Body $Json | Should -Be "paging.sqldataproducer"
        }
    }

    It "returns null for an unknown endpoint" {
        Get-OmadaMockRouteKey -Path "$Base/some/other/endpoint" -Method "GET" | Should -BeNullOrEmpty
    }
}

Describe "Resolve-OmadaMockResponse" {
    It "serves the query-list fixture as JSON containing the seeded queries" {
        $Response = Resolve-OmadaMockResponse -Path "https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING?`$orderby=DisplayName,NAME" -Method "GET"
        $Response.StatusCode | Should -Be 200
        $Response.ContentType | Should -Match "application/json"
        ($Response.Body | ConvertFrom-Json).value.Count | Should -BeGreaterThan 0
    }
    It "serves the data connection dialog as HTML" {
        $Response = Resolve-OmadaMockResponse -Path "https://tenant.omada.cloud/dataobjdlg.aspx?DOID=8801" -Method "GET"
        $Response.ContentType | Should -Match "text/html"
        $Response.Body | Should -Match "OISES"
    }
    It "falls back to an empty 200 for an unknown endpoint" {
        $Response = Resolve-OmadaMockResponse -Path "https://tenant.omada.cloud/nope" -Method "GET"
        $Response.StatusCode | Should -Be 200
        $Response.Body.Trim() | Should -Be "{}"
    }
    It "reports no delay for a route whose manifest entry has no delayMs" {
        $Response = Resolve-OmadaMockResponse -Path "https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING" -Method "GET"
        $Response.DelayMs | Should -Be 0
    }
}

Describe "Get-OmadaMockRouteDelayMs" {
    It "returns the declared delay" {
        Get-OmadaMockRouteDelayMs -Route ([pscustomobject]@{ delayMs = 250 }) | Should -Be 250
    }
    It "returns 0 when the field is absent" {
        Get-OmadaMockRouteDelayMs -Route ([pscustomobject]@{ file = "x.json" }) | Should -Be 0
    }
    It "returns 0 for a null route, a null value and a non-numeric value" {
        Get-OmadaMockRouteDelayMs -Route $null | Should -Be 0
        Get-OmadaMockRouteDelayMs -Route ([pscustomobject]@{ delayMs = $null }) | Should -Be 0
        Get-OmadaMockRouteDelayMs -Route ([pscustomobject]@{ delayMs = "soon" }) | Should -Be 0
    }
    It "clamps a negative delay to 0" {
        Get-OmadaMockRouteDelayMs -Route ([pscustomobject]@{ delayMs = -5 }) | Should -Be 0
    }
}
