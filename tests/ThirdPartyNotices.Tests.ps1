BeforeAll {
    $Script:ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Script:NoticesPath = Join-Path $Script:ParentPath -ChildPath "THIRD-PARTY-NOTICES.md"

    # Read defensively. If the notices file is missing or renamed, reading it here would fail
    # inside BeforeAll and error out every test in this file; leaving the content empty lets the
    # "Should exist at the repository root" test report the actual problem instead.
    $Script:Notices = if (Test-Path $Script:NoticesPath -PathType Leaf) {
        Get-Content -Path $Script:NoticesPath -Raw -Encoding UTF8
    }
    else {
        [string]::Empty
    }
}

Describe 'THIRD-PARTY-NOTICES' -Tag 'Unit' {

    Context 'The notices file itself' {
        It 'Should exist at the repository root' {
            Test-Path $Script:NoticesPath -PathType Leaf | Should -BeTrue
        }

        It 'Should be referenced from the README' {
            $ReadMe = Get-Content -Path (Join-Path $Script:ParentPath -ChildPath "README.md") -Raw -Encoding UTF8
            $ReadMe | Should -Match 'THIRD-PARTY-NOTICES'
        }

        It 'Should be referenced from the nuspec' {
            $Nuspec = Get-Content -Path (Join-Path $Script:ParentPath -ChildPath "OmadaSqlTroubleshooter.nuspec") -Raw -Encoding UTF8
            $Nuspec | Should -Match 'THIRD-PARTY-NOTICES'
        }

        It 'Should list every component that has an entry heading' {
            # A component may not be silently dropped: each expected heading must still be present.
            $ExpectedHeadings = @(
                'Monaco Editor'
                'Codicons'
                'Microsoft.Web.WebView2'
                'Microsoft Edge WebView2 Runtime'
                'OmadaWeb.PS'
            )
            foreach ($Heading in $ExpectedHeadings) {
                $Script:Notices | Should -Match ([regex]::Escape($Heading)) -Because "'$Heading' must remain listed in the notices"
            }
        }
    }

    Context 'Bundled Monaco Editor' {
        It 'Should record the version that is actually bundled in src\Monaco' {
            # The version banner Monaco itself writes into loader.js is the source of truth; the
            # notices file must agree with it, so a Monaco upgrade cannot land without the notices
            # being updated in the same change.
            $LoaderPath = Join-Path $Script:ParentPath -ChildPath "src\Monaco\min\vs\loader.js"
            Test-Path $LoaderPath -PathType Leaf | Should -BeTrue

            $LoaderHead = (Get-Content -Path $LoaderPath -TotalCount 10) -join "`n"
            $BundledMatch = [regex]::Match($LoaderHead, 'Version:\s*(?<Version>\d+\.\d+\.\d+)\((?<Commit>[0-9a-f]+)\)')
            $BundledMatch.Success | Should -BeTrue -Because "loader.js should carry Monaco's version banner"

            $NoticesMatch = [regex]::Match($Script:Notices, '\|\s*Version\s*\|\s*(?<Version>\d+\.\d+\.\d+)\s*\(commit\s*`(?<Commit>[0-9a-f]+)`\)')
            $NoticesMatch.Success | Should -BeTrue -Because "the notices should record a Monaco version and commit"

            $NoticesMatch.Groups['Version'].Value | Should -Be $BundledMatch.Groups['Version'].Value
            $NoticesMatch.Groups['Commit'].Value | Should -Be $BundledMatch.Groups['Commit'].Value
        }

        It 'Should record the licence of the bundled codicon font' {
            Test-Path (Join-Path $Script:ParentPath -ChildPath "src\Monaco\min\vs\base\browser\ui\codicons\codicon\codicon.ttf") -PathType Leaf |
                Should -BeTrue -Because "the codicon entry in the notices describes this file"
            $Script:Notices | Should -Match 'CC BY 4\.0'
        }
    }

    Context 'Declared locations' {
        It 'Should only point at paths that exist in the repository' {
            $DeclaredPaths = [regex]::Matches($Script:Notices, '\|\s*Location in repository\s*\|\s*`(?<Path>[^`]+)`\s*\|') |
                ForEach-Object { $_.Groups['Path'].Value }

            $DeclaredPaths.Count | Should -BeGreaterThan 0 -Because "bundled components must declare where they live"

            foreach ($DeclaredPath in $DeclaredPaths) {
                # Glob entries ("src/Monaco/min/vs/**") are checked as the directory they point at.
                $Relative = ($DeclaredPath -replace '/\*\*$', '') -replace '/', '\'
                $FullPath = Join-Path $Script:ParentPath -ChildPath $Relative
                Test-Path $FullPath | Should -BeTrue -Because "the notices declare '$DeclaredPath'"
            }
        }
    }

    Context 'No redistributable binaries' {
        It 'Should not contain committed executables, libraries or installer packages' {
            # The notices state that neither the WebView2 SDK nor the WebView2 Runtime is
            # redistributed from this repository. This keeps that statement true.
            $Binaries = Get-ChildItem -Path (Join-Path $Script:ParentPath -ChildPath "src") -Recurse -File -Include "*.exe", "*.dll", "*.msi", "*.cab" -ErrorAction SilentlyContinue |
                ForEach-Object { $_.FullName.Substring($Script:ParentPath.Length + 1) }

            $Binaries | Should -BeNullOrEmpty -Because "redistributing binaries would change this project's licence obligations"
        }
    }

    Context 'Runtime download sources' {
        It 'Should record the NuGet source that Install-WebView2 actually downloads from' {
            $InstallWebView2 = Get-Content -Path (Join-Path $Script:ParentPath -ChildPath "src\Lib\Functions\Private\Install-WebView2.ps1") -Raw -Encoding UTF8
            $InstallWebView2 | Should -Match 'https://www\.nuget\.org/api/v2/package/Microsoft\.Web\.WebView2'
            $Script:Notices | Should -Match 'https://www\.nuget\.org/api/v2/package/Microsoft\.Web\.WebView2'
        }
    }
}
