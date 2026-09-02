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
                'Microsoft.SqlServer.TransactSql.ScriptDom'
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

    Context 'Bundled and downloaded dependency sources' {
        # This used to assert that a literal www.nuget.org/api/v2 URL appeared in Install-WebView2.ps1.
        # That function no longer contains a URL at all: the download address comes from
        # src\DependencyLock.psd1. Reading the lock here is both more accurate and stricter - the
        # notices now cannot drift from the pin the module actually ships and verifies.
        #
        # The entry moved from §2 (downloaded, not redistributed) to §1 (redistributed) when the
        # assemblies started being bundled into the package at build time.
        BeforeAll {
            $Script:Lock = Import-PowerShellDataFile -Path (Join-Path $Script:ParentPath -ChildPath "src\DependencyLock.psd1")

            $Script:WebView2Artifact = @($Script:Lock.Artifacts | Where-Object { $_.Id -eq 'Microsoft.Web.WebView2' })[0]

            # Only the Microsoft.Web.WebView2 entry, so these assertions cannot be satisfied - or
            # broken - by text belonging to another component.
            $SectionMatch = [regex]::Match($Script:Notices, '(?s)###\s*1\.3\s*Microsoft\.Web\.WebView2.*?(?=\r?\n---)')
            $Script:WebView2Section = $SectionMatch.Value

            # One section 2 entry at a time, so these assertions cannot be satisfied - or broken - by text
            # belonging to another component. The lookahead stops at the next "### " heading as well
            # as at the section rule, which is what keeps section 2.1 isolated now that section 2.2 follows it.
            function Get-NoticeSection {
                param([string]$Number)

                return [regex]::Match($Script:Notices, ('(?s)###\s*{0}\s.*?(?=\r?\n---|\r?\n###\s)' -f [regex]::Escape($Number))).Value
            }

        }

        # Declared in the Context body, not in BeforeAll: -ForEach data is read during Pester's
        # discovery phase, before any BeforeAll has run.
        #
        # The two lists differ for WebView2 on purpose. Since it is bundled, its pin - version, URL
        # and hash - lives in the §1.3 redistribution entry, and §2.1 is a short cross-reference
        # covering only the fallback download, so repeating the pin there would be a second copy to
        # drift. ScriptDom is downloaded and nothing else, so §2.2 carries both.
        $PinnedArtifact = @(
            @{ Number = '1.3'; Id = 'Microsoft.Web.WebView2' }
            @{ Number = '2.2'; Id = 'Microsoft.SqlServer.TransactSql.ScriptDom' }
        )

        $DownloadedArtifact = @(
            @{ Number = '2.1'; Id = 'Microsoft.Web.WebView2' }
            @{ Number = '2.2'; Id = 'Microsoft.SqlServer.TransactSql.ScriptDom' }
        )

        It 'Should have a Microsoft.Web.WebView2 entry to check' {
            $Script:WebView2Artifact | Should -Not -BeNullOrEmpty -Because 'the lock file must pin the SDK'
            $Script:WebView2Section | Should -Not -BeNullOrEmpty -Because 'the notices must carry a §1.3 entry for it'
        }

        It 'Should list the component as redistributed now that it ships in the package' {
            $Script:WebView2Section | Should -Match 'Location in package' -Because 'a bundled component must say where it lands in the package'
            $Script:Notices | Should -Match 'fetched and hash-verified at build time' -Because "section 1's opening must cover a component that is not committed"
        }

        It 'Should still document the run-time download fallback' {
            # The fallback is what keeps a damaged bundle, and every x86 process, working.
            $Script:Notices | Should -Match '(?s)###\s*2\.1\s*Microsoft\.Web\.WebView2'
            $Script:Notices | Should -Match 'LOCALAPPDATA'
        }

        It 'Should carry a redistribution review that is explicitly not yet signed off' {
            # Bundling moves this component into Fortigi's redistribution obligations. The review is
            # a blocking prerequisite for the first bundled release and must not read as concluded
            # while the placeholder is still there. If someone completes the review, they remove the
            # TODO and this assertion is updated in the same change.
            $Script:WebView2Section | Should -Match 'DRAFT, NOT YET SIGNED OFF'
            $Script:WebView2Section | Should -Match 'TODO: reviewed by'
        }

        It 'Should reproduce the licence text the redistribution grant depends on' {
            # The grant permits binary redistribution only if the copyright notice, the conditions
            # and the disclaimer travel with the distribution. This file is what carries them.
            $Script:WebView2Section | Should -Match 'Copyright \(C\) Microsoft Corporation\. All rights reserved\.'
            $Script:WebView2Section | Should -Match 'Redistributions in binary form must reproduce'
            $Script:WebView2Section | Should -Match 'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS'
        }

        It 'Should carry a section <Number> entry for <Id> that matches the lock file' -ForEach $PinnedArtifact {
            $Artifact = @($Script:Lock.Artifacts | Where-Object { $_.Id -eq $Id })[0]
            $Artifact | Should -Not -BeNullOrEmpty -Because "the lock file must pin '$Id'"

            $Section = Get-NoticeSection -Number $Number
            $Section | Should -Not -BeNullOrEmpty -Because "the notices must carry a section $Number entry for '$Id'"
            $Section | Should -BeLike ('*{0}*' -f $Id) -Because 'the section must actually be about this component'

            # The URL and hash the module downloads and verifies against.
            $Section | Should -BeLike ('*{0}*' -f $Artifact.Url)
            $Section | Should -BeLike ('*{0}*' -f $Artifact.Sha256)
            $Section | Should -Match 'DependencyLock\.psd1'

            # The Version row of this entry specifically. A document-wide search for wording like
            # "resolved at run time" would also hit the prose explaining that it is *not* resolved
            # that way, which is exactly the wrong thing to fail on.
            $VersionRow = [regex]::Match($Section, '(?m)^\|\s*Version\s*\|\s*(?<Value>[^|]*?)\s*\|\s*$')
            $VersionRow.Success | Should -BeTrue -Because 'the entry must record a version'
            $VersionRow.Groups['Value'].Value | Should -BeLike ('*{0}*' -f $Artifact.Version)
        }

        It 'Should name the function that downloads each artefact' -ForEach $DownloadedArtifact {
            $Artifact = @($Script:Lock.Artifacts | Where-Object { $_.Id -eq $Id })[0]
            $Section = Get-NoticeSection -Number $Number
            $Section | Should -BeLike ('*{0}*' -f $Artifact.InstalledBy) -Because 'the notices must say what fetches the component'
        }
    }
}
