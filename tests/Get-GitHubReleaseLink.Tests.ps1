#Requires -Version 7.0
BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Get-GitHubReleaseLink.ps1")

    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)]$Message, $LogType) process { } }

    $Script:ReleaseApi = "https://api.github.com/repos/Fortigi/OmadaSqlTroubleshooter/releases/tags/"
    $Script:ReleasePage = "https://github.com/Fortigi/OmadaSqlTroubleshooter/releases/tag/"

    # Stands in for HttpClient: GetAsync answers from a table of address -> task, and records the
    # addresses asked for. A missing address answers 404.
    function script:New-FakeClient {
        param([hashtable]$Answer = @{})
        $Client = [PSCustomObject]@{ Answer = $Answer; Asked = [System.Collections.Generic.List[string]]::new() }
        $Client | Add-Member -MemberType ScriptMethod -Name GetAsync -Value {
            param($Uri)
            $this.Asked.Add([string]$Uri)
            if ($this.Answer.ContainsKey([string]$Uri)) { return $this.Answer[[string]$Uri] }
            return [System.Threading.Tasks.Task]::FromResult([System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::NotFound))
        }
        $Client
    }
    function script:New-ReleaseAnswer {
        param([string]$Tag, [bool]$Draft = $false)
        $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::OK)
        $Response.Content = [System.Net.Http.StringContent]::new((@{ html_url = "$Script:ReleasePage$Tag"; draft = $Draft } | ConvertTo-Json))
        [System.Threading.Tasks.Task]::FromResult($Response)
    }
}

Describe 'Test-GitHubReleaseVersion' -Tag 'Unit' {
    It 'Should accept a pipeline version (<Version>)' -ForEach @(
        @{ Version = "2026.11.20.160" }
        @{ Version = "2026.1.2.3" }
    ) {
        Test-GitHubReleaseVersion -Version $Version | Should -BeTrue
    }

    It 'Should refuse anything else (<Version>)' -ForEach @(
        @{ Version = "Development" }
        @{ Version = "" }
        @{ Version = "1.0" }
        @{ Version = "2026.11.20" }
        @{ Version = "2026.11.20.160-nightly" }
        @{ Version = "2026.11.20.160/../../x" }
    ) {
        Test-GitHubReleaseVersion -Version $Version | Should -BeFalse
    }
}

Describe 'Get-GitHubReleaseTagCandidate' -Tag 'Unit' {
    It 'Should give the release tag first, then the nightly' {
        Get-GitHubReleaseTagCandidate -Version "2026.11.20.160" | Should -Be @("v2026.11.20.160", "v2026.11.20.160-nightly")
    }
}

Describe 'Get-GitHubReleaseLink' -Tag 'Unit' {
    BeforeEach {
        $Script:GitHubReleaseLinkCache = $null
        Mock Invoke-GitHubReleaseLookup { "$Script:ReleasePage" + "v2026.11.20.160" }
    }

    It 'Should ask GitHub about both tags of a pipeline version' {
        Get-GitHubReleaseLink -Version "2026.11.20.160" -TimeoutMilliseconds 1500 | Should -Be "$($Script:ReleasePage)v2026.11.20.160"

        Should -Invoke Invoke-GitHubReleaseLookup -Times 1 -Exactly -ParameterFilter { ($Tag -join ",") -eq "v2026.11.20.160,v2026.11.20.160-nightly" -and $TimeoutMilliseconds -eq 1500 }
    }

    It 'Should ask nothing for a version that cannot have a release' {
        Get-GitHubReleaseLink -Version "Development" | Should -BeNullOrEmpty
        Should -Invoke Invoke-GitHubReleaseLookup -Times 0 -Exactly
    }

    It 'Should ask once per session, a "no" included' {
        Mock Invoke-GitHubReleaseLookup { $null }

        Get-GitHubReleaseLink -Version "2026.11.20.160" | Should -BeNullOrEmpty
        Get-GitHubReleaseLink -Version "2026.11.20.160" | Should -BeNullOrEmpty

        Should -Invoke Invoke-GitHubReleaseLookup -Times 1 -Exactly
    }

    It 'Should ask again for another version' {
        $null = Get-GitHubReleaseLink -Version "2026.11.20.160"
        $null = Get-GitHubReleaseLink -Version "2026.11.21.161"

        Should -Invoke Invoke-GitHubReleaseLookup -Times 2 -Exactly
    }

    It 'Should default to the running version' {
        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationVersion = "2026.11.13.63" }

        $null = Get-GitHubReleaseLink

        Should -Invoke Invoke-GitHubReleaseLookup -Times 1 -Exactly -ParameterFilter { $Tag[0] -eq "v2026.11.13.63" }
    }
}

Describe 'Invoke-GitHubReleaseLookup' -Tag 'Unit' {
    It 'Should give the page of the release tag' {
        $Client = New-FakeClient -Answer @{ "$($Script:ReleaseApi)v1" = (New-ReleaseAnswer -Tag "v1") }

        Invoke-GitHubReleaseLookup -Tag "v1", "v1-nightly" -Client $Client | Should -Be "$($Script:ReleasePage)v1"
        $Client.Asked | Should -Be @("$($Script:ReleaseApi)v1", "$($Script:ReleaseApi)v1-nightly")
    }

    It 'Should give the nightly''s page when only the nightly has a release' {
        $Client = New-FakeClient -Answer @{ "$($Script:ReleaseApi)v1-nightly" = (New-ReleaseAnswer -Tag "v1-nightly") }

        Invoke-GitHubReleaseLookup -Tag "v1", "v1-nightly" -Client $Client | Should -Be "$($Script:ReleasePage)v1-nightly"
    }

    It 'Should prefer the tags in the order given' {
        $Client = New-FakeClient -Answer @{
            "$($Script:ReleaseApi)v1"         = (New-ReleaseAnswer -Tag "v1")
            "$($Script:ReleaseApi)v1-nightly" = (New-ReleaseAnswer -Tag "v1-nightly")
        }

        Invoke-GitHubReleaseLookup -Tag "v1", "v1-nightly" -Client $Client | Should -Be "$($Script:ReleasePage)v1"
    }

    It 'Should give nothing when neither tag has a release' {
        Invoke-GitHubReleaseLookup -Tag "v1", "v1-nightly" -Client (New-FakeClient) | Should -BeNullOrEmpty
    }

    It 'Should not wait past the timeout for an answer' {
        $Never = [System.Threading.Tasks.TaskCompletionSource[System.Net.Http.HttpResponseMessage]]::new()
        $Client = New-FakeClient -Answer @{ "$($Script:ReleaseApi)v1" = $Never.Task; "$($Script:ReleaseApi)v1-nightly" = (New-ReleaseAnswer -Tag "v1-nightly") }
        $Clock = [System.Diagnostics.Stopwatch]::StartNew()

        Invoke-GitHubReleaseLookup -Tag "v1", "v1-nightly" -TimeoutMilliseconds 200 -Client $Client | Should -Be "$($Script:ReleasePage)v1-nightly"
        $Clock.ElapsedMilliseconds | Should -BeLessThan 3000
    }

    It 'Should give nothing, without throwing, when the request fails' {
        $Failed = [System.Threading.Tasks.Task]::FromException[System.Net.Http.HttpResponseMessage]([System.Net.Http.HttpRequestException]::new("blocked"))
        $Client = New-FakeClient -Answer @{ "$($Script:ReleaseApi)v1" = $Failed }

        Invoke-GitHubReleaseLookup -Tag "v1" -Client $Client | Should -BeNullOrEmpty
    }

    It 'Should escape the tag in the address' {
        $Client = New-FakeClient

        $null = Invoke-GitHubReleaseLookup -Tag "v1/../x y" -Client $Client

        $Client.Asked | Should -Be @("$($Script:ReleaseApi)v1%2F..%2Fx%20y")
    }
}

Describe 'ConvertFrom-GitHubReleaseResponse' -Tag 'Unit' {
    It 'Should give the page of a published release' {
        ConvertFrom-GitHubReleaseResponse -StatusCode 200 -Content (@{ html_url = "$($Script:ReleasePage)v1"; draft = $false } | ConvertTo-Json) | Should -Be "$($Script:ReleasePage)v1"
    }

    It 'Should give nothing for <Case>' -ForEach @(
        @{ Case = 'a 404'; Status = 404; Content = '{"html_url":"https://github.com/Fortigi/OmadaSqlTroubleshooter/releases/tag/v1"}' }
        @{ Case = 'a draft'; Status = 200; Content = '{"html_url":"https://github.com/Fortigi/OmadaSqlTroubleshooter/releases/tag/v1","draft":true}' }
        @{ Case = 'another repository'; Status = 200; Content = '{"html_url":"https://github.com/someone/else/releases/tag/v1"}' }
        @{ Case = 'another site'; Status = 200; Content = '{"html_url":"https://example.com/Fortigi/OmadaSqlTroubleshooter/releases/tag/v1"}' }
        @{ Case = 'no address'; Status = 200; Content = '{}' }
        @{ Case = 'no body'; Status = 200; Content = '' }
        @{ Case = 'a body that is not JSON'; Status = 200; Content = '<html>' }
    ) {
        ConvertFrom-GitHubReleaseResponse -StatusCode $Status -Content $Content | Should -BeNullOrEmpty
    }
}
