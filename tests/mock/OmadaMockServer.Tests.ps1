#Requires -Version 7.0
# Round-trip tests: start the real mock server and assert each endpoint returns the shape the app
# consumes. Cross-platform (TcpListener + Invoke-RestMethod), uses an OS-assigned port to avoid clashes.

BeforeAll {
    . (Join-Path $PSScriptRoot "OmadaMockRouter.ps1")
    . (Join-Path $PSScriptRoot "OmadaMockServer.ps1")

    $script:Handle = New-OmadaMockServerHandle -BindAddress "127.0.0.1" -Port 0
    $script:BaseUrl = $script:Handle.BaseUrl

    function script:Get-Mock {
        param([string]$PathAndQuery, [string]$Method = "GET", $Body)
        $Params = @{ Uri = "$script:BaseUrl$PathAndQuery"; Method = $Method; NoProxy = $true; TimeoutSec = 5 }
        if ($null -ne $Body) {
            $Params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
            $Params.ContentType = "application/json"
        }
        return Invoke-RestMethod @Params
    }
}

AfterAll {
    if ($null -ne $script:Handle) { Stop-OmadaMockServerHandle -Handle $script:Handle }
}

Describe "Mock server over HTTP" {
    It "answers the connection probe with 200" {
        { Get-Mock -PathAndQuery "/odata/dataobjects/C_P_SQLTROUBLESHOOTING" } | Should -Not -Throw
    }
    It "returns a non-empty query list with Id + DisplayName" {
        $Result = Get-Mock -PathAndQuery "/odata/dataobjects/C_P_SQLTROUBLESHOOTING?`$orderby=DisplayName,NAME&`$filter=Deleted ne true"
        $Result.value.Count | Should -BeGreaterThan 0
        $Result.value[0].Id | Should -Not -BeNullOrEmpty
        $Result.value[0].DisplayName | Should -Not -BeNullOrEmpty
    }
    It "returns a single query object carrying C_QUERY" {
        $Result = Get-Mock -PathAndQuery "/odata/dataobjects/C_P_SQLTROUBLESHOOTING(10521)"
        $Result.C_QUERY | Should -Match "SELECT"
    }
    It "returns a schema keyed by schema.table" {
        $Result = Get-Mock -PathAndQuery "/webservice/SyntaxHighlighting.asmx/GetSqlSchema" -Method "POST" -Body @{ connectionId = 4201 }
        $Result.d | Should -Not -BeNullOrEmpty
        ($Result.d.PSObject.Properties.Name -contains "dbo.tblDataObject") | Should -BeTrue
    }
    It "returns the SQL Troubleshooting view row" {
        $Result = Get-Mock -PathAndQuery "/WebService/JQGridPopulationWebService.asmx/GetPagingData" -Method "POST" -Body @{ dataType = "Views" }
        ($Result.d.Rows | Where-Object { $_.Name -eq "SQL Troubleshooting" }).Count | Should -BeGreaterThan 0
    }
    It "returns executable result rows for SqlDataProducer" {
        $Result = Get-Mock -PathAndQuery "/webservice/jQGridPopulationWebService.asmx/GetPagingData" -Method "POST" -Body @{ dataType = "SqlDataProducer" }
        $Result.d.Rows.Count | Should -BeGreaterThan 0
        $Result.d.Records | Should -BeGreaterThan 0
    }
    It "returns history rows whose ChangedFields decode to SQL Query changes" {
        $Result = Get-Mock -PathAndQuery "/webservice/jQGridPopulationWebService.asmx/GetPagingData" -Method "POST" -Body @{ dataType = "DataObjectHistory" }
        $Fields = $Result.d.Rows[0].ChangedFields | ConvertFrom-Json
        ($Fields | Where-Object { $_.Field -eq "SQL Query" }).Count | Should -BeGreaterThan 0
    }
    It "returns data connection HTML the app can parse into options" {
        # Must assert on the RAW markup: the app hands this response to
        # Get-DataConnectionOptionList -Html ([string]). Invoke-RestMethod would deserialize the
        # text/html body into an [XmlDocument] that stringifies to "System.Xml.XmlDocument" and
        # matches no <option> - the exact failure the transport shim now avoids.
        $Response = Invoke-WebRequest -Uri "$script:BaseUrl/dataobjdlg.aspx?DOID=8801" -NoProxy -TimeoutSec 5
        $Response.Content | Should -BeOfType [string]
        $Response.Content | Should -Match "OISES"
        [regex]::Matches($Response.Content, '<option.*?value="(\d+).*?data-uid="(.*?)".*?>(.*?)</option>').Count | Should -BeGreaterThan 0
    }
}
