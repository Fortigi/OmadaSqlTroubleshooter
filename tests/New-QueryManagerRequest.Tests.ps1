#Requires -Version 7.0
BeforeAll { . (Join-Path $PSScriptRoot "QueryManager.Shared.ps1"); $script:Base = "https://tenant.omada.cloud" }

Describe 'New-QueryManagerRequest' -Tag 'Unit' {
    It 'Should list every query, deleted ones included, ordered by name' {
        $Request = New-QueryManagerRequest -Kind QueryObjectList -Context @{ BaseUrl = $script:Base }

        $Request.Method | Should -Be "GET"
        $Request.Uri | Should -Be "$script:Base/odata/dataobjects/C_P_SQLTROUBLESHOOTING?DeletedStatus=Both&`$orderby=DisplayName,NAME"
        $Request.Body | Should -BeNullOrEmpty
    }

    It 'Should restore a deleted query through the undelete web service' {
        $Request = New-QueryManagerRequest -Kind RestoreQuery -Context @{ BaseUrl = $script:Base; QueryDoId = 4711 }

        $Request.Method | Should -Be "POST"
        $Request.Uri | Should -Be "$script:Base/WebService/DataObjectWebService.asmx/UndeleteDataObject"
        ($Request.Body | ConvertFrom-Json).id | Should -Be 4711
    }

    It 'Should read one query by id' {
        $Request = New-QueryManagerRequest -Kind QueryObject -Context @{ BaseUrl = $script:Base; QueryDoId = 42 }

        $Request.Method | Should -Be "GET"
        $Request.Uri | Should -Be "$script:Base/odata/dataobjects/C_P_SQLTROUBLESHOOTING(42)"
    }

    It 'Should create a query with its name, text and data connection' {
        $Request = New-QueryManagerRequest -Kind CreateQuery -Context @{ BaseUrl = $script:Base; QueryName = "New"; QueryText = "-- New"; DataConnectionDoId = "3" }

        $Request.Method | Should -Be "POST"
        $Request.Uri | Should -Be "$script:Base/odata/dataobjects/C_P_SQLTROUBLESHOOTING"
        $Request.Body.NAME | Should -Be "New"
        $Request.Body.C_QUERY | Should -Be "-- New"
        $Request.Body.C_SQLTROUBLESHOOTING_DATACONNECTION.Id | Should -Be "3"
    }

    It 'Should create a query without a data connection when none is selected' {
        $Request = New-QueryManagerRequest -Kind CreateQuery -Context @{ BaseUrl = $script:Base; QueryName = "New"; QueryText = "" }

        $Request.Body.ContainsKey("C_SQLTROUBLESHOOTING_DATACONNECTION") | Should -BeFalse
    }

    It 'Should read one query''s history, newest first, with every row' {
        $Request = New-QueryManagerRequest -Kind QueryHistory -Context @{ BaseUrl = $script:Base; QueryDoId = 42 }

        $Request.Method | Should -Be "POST"
        $Request.Uri | Should -Be "$script:Base/webservice/jQGridPopulationWebService.asmx/GetPagingData"
        $Request.Body.dataType | Should -Be "DataObjectHistory"
        $Request.Body.dataTypeArgs.dataObjectId | Should -Be 42
        $Request.Body.dataTypeArgs.propertyId | Should -Be 0
        $Request.Body.dataTypeArgs.userId | Should -Be 0
        $Request.Body.page | Should -Be 1
        $Request.Body.rows | Should -Be 100000
        $Request.Body.sidx | Should -Be "when"
        $Request.Body.sord | Should -Be "desc"
        $Request.Body._search | Should -BeFalse
    }
}
