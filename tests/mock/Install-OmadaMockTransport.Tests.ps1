#Requires -Version 7.0
# Tests the replay transport shim against a real running mock server. This is the seam the app uses
# instead of OmadaWeb.PS, so it must hand back exactly what the app's callers expect: deserialized
# objects for JSON endpoints and RAW markup for the HTML data-connection dialog.

BeforeAll {
    . (Join-Path $PSScriptRoot "OmadaMockRouter.ps1")
    . (Join-Path $PSScriptRoot "OmadaMockServer.ps1")
    . (Join-Path $PSScriptRoot "Install-OmadaMockTransport.ps1")

    # The REAL app parser, so this asserts the actual consumption path rather than a copy of it.
    $RepoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    . (Join-Path $RepoRoot "src\Lib\Functions\Private\Get-DataConnectionOptionList.ps1")

    $script:Handle = New-OmadaMockServerHandle -BindAddress "127.0.0.1" -Port 0
    Install-OmadaMockTransport -MockBaseUrl $script:Handle.BaseUrl
}

AfterAll {
    if ($null -ne $script:Handle) { Stop-OmadaMockServerHandle -Handle $script:Handle }
}

Describe "Replay transport shim" {
    It "rewrites a real tenant URL onto the mock and returns deserialized JSON" {
        # The app builds https://<tenant>.omada.cloud/... - the shim must retarget it at the mock.
        $Result = Invoke-OmadaRestMethod -Uri "https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING?`$orderby=DisplayName,NAME" -Method "GET"
        $Result.value.Count | Should -BeGreaterThan 0
        $Result.value[0].DisplayName | Should -Not -BeNullOrEmpty
    }

    It "returns the data connection dialog as a raw string the option regex can parse" {
        # Regression: Invoke-RestMethod would deserialize text/html into an [XmlDocument], which
        # stringifies to "System.Xml.XmlDocument" and yields zero data connections in the app.
        $Html = Invoke-OmadaRestMethod -Uri "https://tenant.omada.cloud/dataobjdlg.aspx?DOID=8801" -Method "GET"
        $Html | Should -BeOfType [string]
        $Options = Get-DataConnectionOptionList -Html $Html
        $Options.Count | Should -BeGreaterThan 0
        ($Options -join "|") | Should -Match "OISES"
    }

    It "posts a hashtable body as JSON and routes on its dataType" {
        $Body = @{ dataType = "SqlDataProducer"; dataTypeArgs = @{ targetId = 10521 }; page = 1 }
        $Result = Invoke-OmadaRestMethod -Uri "https://tenant.omada.cloud/webservice/jQGridPopulationWebService.asmx/GetPagingData" -Method "POST" -Body $Body
        $Result.d.Rows.Count | Should -BeGreaterThan 0
    }

    It "tolerates the extra RestMethodParam keys the app splats" {
        $Result = Invoke-OmadaRestMethod -Uri "https://tenant.omada.cloud/odata/dataobjects/C_P_SQLTROUBLESHOOTING" -Method "GET" `
            -AuthenticationType "WebView2" -UseWebView2 $false -EntraApplicationIdUri $null -EntraIdTenantId $null `
            -ForceAuthentication $false -InPrivate $false -SessionKey "abc" -Credential $null
        $Result | Should -Not -BeNullOrEmpty
    }
}
