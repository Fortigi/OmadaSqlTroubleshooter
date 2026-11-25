#Requires -Version 7.0
BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = [System.IO.Path]::Combine($Script:RepositoryRoot, "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Open-HelpForm.ps1")

    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$Message, $LogType)
        process { $script:Log += , [PSCustomObject]@{ Message = $Message; LogType = $LogType } }
    }
}

Describe 'Get-HelpLink' -Tag 'Unit' {
    It 'Should give the <Name> address' -ForEach @(
        @{ Name = "Project"; Expected = "https://github.com/Fortigi/OmadaSqlTroubleshooter" }
        @{ Name = "Gallery"; Expected = "https://www.powershellgallery.com/packages/OmadaSqlTroubleshooter" }
        @{ Name = "Issues"; Expected = "https://github.com/Fortigi/OmadaSqlTroubleshooter/issues" }
        @{ Name = "Bug"; Expected = "https://github.com/Fortigi/OmadaSqlTroubleshooter/issues/new?template=bug_report.yml" }
        @{ Name = "Feature"; Expected = "https://github.com/Fortigi/OmadaSqlTroubleshooter/issues/new?template=feature_request.yml" }
    ) {
        Get-HelpLink -Name $Name | Should -BeExactly $Expected
    }

    It 'Should point at the project the module manifest names' {
        $Manifest = Import-PowerShellDataFile -Path ([System.IO.Path]::Combine($Script:RepositoryRoot, "src", "OmadaSqlTroubleshooter.psd1"))
        Get-HelpLink -Name Project | Should -BeExactly $Manifest.PrivateData.PSData.ProjectUri
    }
}

Describe 'New-GitHubIssueUrl' -Tag 'Unit' {
    It 'Should fill in the versions of a bug report, escaped, in the form''s field ids' {
        $Url = New-GitHubIssueUrl -Kind Bug -Version @{
            "module-version"      = "2026.11.25.1"
            "omadaweb-ps-version" = "2026.10.15.51"
            "powershell-version"  = "7.4.6"
            "os-version"          = "Microsoft Windows NT 10.0.22631.0"
        }

        $Url | Should -BeExactly ("https://github.com/Fortigi/OmadaSqlTroubleshooter/issues/new?template=bug_report.yml" +
            "&module-version=2026.11.25.1&omadaweb-ps-version=2026.10.15.51&powershell-version=7.4.6&os-version=Microsoft%20Windows%20NT%2010.0.22631.0")
    }

    It 'Should leave out a version that is not known, and anything that is not a version field' {
        $Url = New-GitHubIssueUrl -Kind Bug -Version @{ "module-version" = " "; "powershell-version" = "7.4.6"; "tenant" = "contoso" }

        $Url | Should -BeExactly "https://github.com/Fortigi/OmadaSqlTroubleshooter/issues/new?template=bug_report.yml&powershell-version=7.4.6"
    }

    It 'Should fill in nothing for a feature request' {
        New-GitHubIssueUrl -Kind Feature -Version @{ "module-version" = "1" } | Should -BeExactly "https://github.com/Fortigi/OmadaSqlTroubleshooter/issues/new?template=feature_request.yml"
    }
}

Describe 'Get-IssueVersionInfo' -Tag 'Unit' {
    It 'Should read the versions of this session' {
        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationVersion = "2026.11.25.1" }
        Mock Get-Module { [PSCustomObject]@{ Version = [version]"2026.10.15.51" } } -ParameterFilter { $Name -eq "OmadaWeb.PS" }

        $Info = Get-IssueVersionInfo

        $Info["module-version"] | Should -Be "2026.11.25.1"
        $Info["omadaweb-ps-version"] | Should -Be "2026.10.15.51"
        $Info["powershell-version"] | Should -Be ([string]$PSVersionTable.PSVersion)
        $Info["os-version"] | Should -Not -BeNullOrEmpty
    }

    It 'Should leave OmadaWeb.PS empty when it is not loaded' {
        Mock Get-Module { } -ParameterFilter { $Name -eq "OmadaWeb.PS" }
        (Get-IssueVersionInfo)["omadaweb-ps-version"] | Should -Be ""
    }
}

Describe 'Open-GitHubIssue' -Tag 'Unit' {
    BeforeEach {
        Mock Open-HelpUrl { }
        Mock Get-IssueVersionInfo { @{ "powershell-version" = "7.4.6" } }
    }

    It 'Should open a bug report with the session''s versions' {
        Open-GitHubIssue -Kind Bug

        Should -Invoke Open-HelpUrl -Times 1 -Exactly -ParameterFilter { $Url -like "*template=bug_report.yml&powershell-version=7.4.6" }
    }

    It 'Should open a feature request without reading any versions' {
        Open-GitHubIssue -Kind Feature

        Should -Invoke Get-IssueVersionInfo -Times 0 -Exactly
        Should -Invoke Open-HelpUrl -Times 1 -Exactly -ParameterFilter { $Url -like "*template=feature_request.yml" }
    }
}

Describe 'Open-GitHubReleaseNotes' -Tag 'Unit' {
    BeforeAll {
        function Get-GitHubReleaseLink { }
    }
    BeforeEach {
        $script:Log = @()
        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationVersion = "2026.11.21.999" }
        Mock Open-HelpUrl { }
    }

    It 'Should open the release page' {
        Mock Get-GitHubReleaseLink { "https://github.com/Fortigi/OmadaSqlTroubleshooter/releases/tag/v2026.11.13.63" }

        Open-GitHubReleaseNotes

        Should -Invoke Open-HelpUrl -Times 1 -Exactly -ParameterFilter { $Url -eq "https://github.com/Fortigi/OmadaSqlTroubleshooter/releases/tag/v2026.11.13.63" }
    }

    It 'Should warn, and open nothing, when the version has no release' {
        Mock Get-GitHubReleaseLink { $null }

        Open-GitHubReleaseNotes

        Should -Invoke Open-HelpUrl -Times 0 -Exactly
        ($script:Log | Where-Object LogType -eq "WARNING").Message | Should -Match "2026.11.21.999 has no release"
    }
}

Describe 'Open-HelpUrl' -Tag 'Unit' {
    BeforeEach {
        $script:Log = @()
        Mock Start-Process { }
    }

    It 'Should open a project address (<Url>)' -ForEach @(
        @{ Url = "https://github.com/Fortigi/OmadaSqlTroubleshooter/issues" }
        @{ Url = "https://www.powershellgallery.com/packages/OmadaSqlTroubleshooter" }
    ) {
        Open-HelpUrl -Url $Url

        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq $Url }
    }

    It 'Should refuse, with a warning, anything else (<Url>)' -ForEach @(
        @{ Url = "http://github.com/Fortigi/OmadaSqlTroubleshooter" }
        @{ Url = "https://github.com.evil.example/x" }
        @{ Url = "https://example.com/" }
        @{ Url = "file:///C:/Windows/System32/calc.exe" }
        @{ Url = "calc.exe" }
    ) {
        Open-HelpUrl -Url $Url

        Should -Invoke Start-Process -Times 0 -Exactly
        ($script:Log | Where-Object LogType -eq "WARNING").Message | Should -Match "Not opening"
    }
}
