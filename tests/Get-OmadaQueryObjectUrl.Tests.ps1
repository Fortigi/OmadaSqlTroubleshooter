#Requires -Version 7.0
BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Get-OmadaQueryObjectUrl.ps1")

    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$Message, $LogType)
        process { $script:Log += , [PSCustomObject]@{ Message = $Message; LogType = $LogType } }
    }
}

Describe 'Get-OmadaQueryObjectUrl' -Tag 'Unit' {
    It 'Should build the data object page address (<BaseUrl>)' -ForEach @(
        @{ BaseUrl = "https://tenant.omada.cloud"; Expected = "https://tenant.omada.cloud/dataobjdlg.aspx?DOID=1234" }
        @{ BaseUrl = "https://tenant.omada.cloud/"; Expected = "https://tenant.omada.cloud/dataobjdlg.aspx?DOID=1234" }
        @{ BaseUrl = "http://omada.local/OIS"; Expected = "http://omada.local/OIS/dataobjdlg.aspx?DOID=1234" }
    ) {
        Get-OmadaQueryObjectUrl -BaseUrl $BaseUrl -DoId "1234" | Should -BeExactly $Expected
    }

    It 'Should give nothing for a tenant URL that is not an absolute web address (<BaseUrl>)' -ForEach @(
        @{ BaseUrl = $null }
        @{ BaseUrl = "" }
        @{ BaseUrl = "tenant.omada.cloud" }
        @{ BaseUrl = "file:///C:/Windows/System32/calc.exe" }
        @{ BaseUrl = "ftp://tenant.omada.cloud" }
    ) {
        Get-OmadaQueryObjectUrl -BaseUrl $BaseUrl -DoId "1234" | Should -BeNullOrEmpty
    }

    It 'Should give nothing for an id that is not a number (<DoId>)' -ForEach @(
        @{ DoId = $null }
        @{ DoId = "" }
        @{ DoId = "12a" }
        @{ DoId = "1234&x=1" }
        @{ DoId = " 1234" }
    ) {
        Get-OmadaQueryObjectUrl -BaseUrl "https://tenant.omada.cloud" -DoId $DoId | Should -BeNullOrEmpty
    }
}

Describe 'Open-OmadaQueryObject' -Tag 'Unit' {
    BeforeEach {
        $script:Log = @()
        $Script:AppConfig = [PSCustomObject]@{ BaseUrl = "https://tenant.omada.cloud" }
        Mock Start-Process { }
    }

    It 'Should open the query''s page in the default browser' {
        Open-OmadaQueryObject -DoId "77"

        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq "https://tenant.omada.cloud/dataobjdlg.aspx?DOID=77" }
        ($script:Log | Where-Object LogType -eq "WARNING") | Should -BeNullOrEmpty
    }

    It 'Should warn and open nothing when no address can be built' {
        $Script:AppConfig.BaseUrl = "not a url"

        Open-OmadaQueryObject -DoId "77"

        Should -Invoke Start-Process -Times 0 -Exactly
        ($script:Log | Where-Object LogType -eq "WARNING").Message | Should -Match "query 77"
    }
}
