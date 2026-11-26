#Requires -Version 7.0
BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Get-OmadaIdentityUserName.ps1")
    function Invoke-OmadaPSWebRequestWrapper { }
}

Describe 'ConvertFrom-IdentityUserNamePage' -Tag 'Unit' {
    It 'Should read the name from the page (<Case>)' -ForEach @(
        @{ Case = 'quoted'; Page = "var s = { identityUserName: 'CORP\ann', other: 1 };"; Expected = "CORP\ann" }
        @{ Case = 'bare'; Page = "identityUserName: ann@corp.example,"; Expected = "ann@corp.example" }
    ) {
        ConvertFrom-IdentityUserNamePage -Content $Page | Should -BeExactly $Expected
    }

    It 'Should give nothing for <Case>' -ForEach @(
        @{ Case = 'a page without it'; Page = "<html></html>" }
        @{ Case = 'an empty name'; Page = "identityUserName: '',"; }
        @{ Case = 'no page'; Page = $null }
    ) {
        ConvertFrom-IdentityUserNamePage -Content $Page | Should -BeNullOrEmpty
    }
}

Describe 'Get-OmadaIdentityUserName' -Tag 'Unit' {
    It 'Should read the active tab''s user settings page' {
        $Script:AppConfig = [PSCustomObject]@{ BaseUrl = "https://t" }
        $Script:RunTimeData = [PSCustomObject]@{ RestMethodParam = [PSCustomObject]@{ Uri = $null; Body = "x"; Method = $null } }
        Mock Invoke-OmadaPSWebRequestWrapper { "identityUserName: 'CORP\ann'," }

        Get-OmadaIdentityUserName | Should -Be "CORP\ann"

        $Script:RunTimeData.RestMethodParam.Uri | Should -Be "https://t/actusersettingsdlg.aspx?HIDEBACKARRICON=1"
        $Script:RunTimeData.RestMethodParam.Method | Should -Be "GET"
        $Script:RunTimeData.RestMethodParam.Body | Should -BeNullOrEmpty
    }
}
