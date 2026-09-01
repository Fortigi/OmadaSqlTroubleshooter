Properties {
    $Version = $BuildVersion
    $AllowPrerelease = [bool]::Parse($AllowPrerelease.ToLower())
    $Date = Get-Date
    $ModuleName = "OmadaSqlTroubleShooter"
    $ParentPath = (Get-Item -Path $PSScriptRoot -Verbose:$false).Parent.FullName
    $ModuleSource = Join-Path -Path $ParentPath -ChildPath 'src'
    $TestSource = Join-Path -Path $ParentPath -ChildPath 'tests'
    $OutputDir = Join-Path -Path $ParentPath -ChildPath 'buildoutput\OmadaSqlTroubleShooter'
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null

    # Where Task Dependencies lays the hash-verified WebView2 assemblies out, and where
    # Resolve-WebView2AssemblyPath looks for them at run time. The layout mirrors
    # %LOCALAPPDATA%\OmadaSqlTroubleshooter\Bin\win-x64 so load-time resolution is a single "which
    # directory?" decision. x64 only: the manifest declares ProcessorArchitecture = 'Amd64', and x86
    # falls back to the runtime download.
    $BundleDir = Join-Path -Path $OutputDir -ChildPath 'Bin\WebView2Dlls\win-x64'

    # When set (PR validation only), scopes Analyze/Test to just these files so unrelated pre-existing issues don't block unrelated PRs.
    $ChangedFiles = @()
    if ($env:PR_CHANGED_FILES) {
        $ChangedFiles = $env:PR_CHANGED_FILES -split ';' | Where-Object { $_ } | ForEach-Object {
            (Resolve-Path -Path (Join-Path $ParentPath $_) -ErrorAction SilentlyContinue).Path
        } | Where-Object { $_ }
    }
}

Task default -Depends Analyze, Test, Build, TestAssemblies, ImportModule
Task TestBuildOnly -Depends Analyze, Test, Build, TestAssemblies
Task Pipeline -Depends Analyze, Test, Build, TestAssemblies
Task DeployOnly -Depends Build, Deploy

# End-to-end suite: launches the REAL app against a fully mocked Omada backend and drives every
# scenario unattended. Deliberately NOT part of default/Pipeline/TestBuildOnly - it needs the local
# GUI runtime (STA, WebView2, OmadaWeb.PS) and so is a local-only lane. Run: ./build/build.ps1 -Task E2E
Task E2E {
    $E2ELauncher = Join-Path $TestSource -ChildPath 'e2e\Invoke-E2ESuite.ps1'
    "Running end-to-end suite (real app, mocked backend)..." | Write-Host -ForegroundColor Cyan
    & pwsh -NoProfile -File $E2ELauncher
    if ($LASTEXITCODE -ne 0) {
        throw "End-to-end suite failed (exit $LASTEXITCODE). See buildoutput\E2EResults.xml."
    }
}


function Get-GalleryModuleVersion {
    [CmdLetBinding()]
    param (
        [string]$ModuleName,
        [switch]$AllowPrerelease
    )

    try {
        $ApiEndpoint = "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='{0}'" -f $ModuleName
        $Response = Invoke-RestMethod -Uri $ApiEndpoint -Method Get -Headers @{
            "Accept" = "application/xml"
        } -ConnectionTimeoutSeconds 1

        if ($null -ne $Response) {
            if ($AllowPrerelease) {
                $LatestVersion = $Response | Sort-Object { $_.properties.Published.'#text' } -Descending | Select-Object -First 1
            }
            else {
                $LatestVersion = $Response | Sort-Object { $_.properties.Published.'#text' } -Descending | Where-Object { $_.properties.IsPrerelease.'#text' -ne "true" } | Select-Object -First 1
            }

            return $LatestVersion.properties.Version
        }
        else {
            return $null
        }
    }
    catch {
        return $null
    }
}

Task VerifyDependencyLock {
    try {
        # The module refuses to download anything that is not pinned with a SHA-256 in
        # src\DependencyLock.psd1, so a lock file that has drifted from build\Dependencies is a broken
        # build, not a warning. -SkipDownload keeps local builds offline; CI runs the same script
        # without it, which additionally re-hashes what the pinned URL actually serves.
        "Verify dependency lock" | Write-Host
        & "$PSScriptRoot\Update-DependencyLock.ps1" -Check -SkipDownload
    }
    catch {
        throw $_
        exit 1
    }
}

Task Analyze -Depends VerifyDependencyLock {

    try {
        $SaProfile = @{
            Severity     = @('Error', 'Warning')
            IncludeRules = '*'
            ExcludeRules = '*WriteHost', '*AvoidUsingEmptyCatchBlock*', '*UseShouldProcessForStateChangingFunctions*', '*AvoidOverwritingBuiltInCmdlets*', '*UseToExportFieldsInManifest*', '*UseProcessBlockForPipelineCommand*', '*ConvertToSecureStringWithPlainText*', '*UseSingularNouns*'
        }
        $SaResults = @()
        @("functions") | ForEach-Object {
            $LibSource = $_
            $SourceChildPath = "lib\{0}" -f $LibSource
            Get-ChildItem -Path (Join-Path $ModuleSource -ChildPath $SourceChildPath) -Recurse -File | Where-Object { $_.Name -notlike "_*.ps1" } | Where-Object { $ChangedFiles.Count -eq 0 -or $_.FullName -in $ChangedFiles } | ForEach-Object {
                $SaResults += Invoke-ScriptAnalyzer -Path $_.FullName -Severity @('Error', 'Warning') -Recurse -Profile $SaProfile -Verbose:$false
            }
        }
        $SaProfile = @{
            Severity     = @('Error', 'Warning')
            IncludeRules = '*'
            ExcludeRules = '*WriteHost', '*AvoidUsingEmptyCatchBlock*', '*UseShouldProcessForStateChangingFunctions*', '*AvoidOverwritingBuiltInCmdlets*', '*UseToExportFieldsInManifest*', '*UseProcessBlockForPipelineCommand*', '*ConvertToSecureStringWithPlainText*', '*UseSingularNouns*', 'PSAvoidAssignmentToAutomaticVariable', 'PSReviewUnusedParameter'
        }
        @("events") | ForEach-Object {
            $LibSource = $_
            $SourceChildPath = "lib\{0}" -f $LibSource
            Get-ChildItem -Path (Join-Path $ModuleSource -ChildPath $SourceChildPath) -Recurse -File | Where-Object { $_.Name -notlike "_*.ps1" } | Where-Object { $ChangedFiles.Count -eq 0 -or $_.FullName -in $ChangedFiles } | ForEach-Object {
                $SaResults += Invoke-ScriptAnalyzer -Path $_.FullName -Severity @('Error', 'Warning') -Recurse -Profile $SaProfile -Verbose:$false
            }
        }
        if ($SaResults) {
            $SaResults | Format-Table
            Write-Error -Message 'One or more Script Analyzer errors/warnings where found. Build cannot continue!' -ErrorAction "Stop"
        }
    }
    catch {
        throw $_
        exit 1
    }
}

Task Test -Depends Analyze {
    try {
        $TestFiles = Get-ChildItem -Path $TestSource -Filter '*.Tests.ps1' -Recurse

        # Suites that guard repository-level invariants rather than one function. The filter below
        # maps <Name>.Tests.ps1 to a changed <Name>.ps1, which these have no counterpart for - so
        # without this allowlist, bumping a pin or editing the notices would skip the very tests that
        # exist to catch a bad bump or a stale notice.
        $AlwaysRunTestFile = @(
            'DependencyLock.Tests.ps1'
            'ThirdPartyNotices.Tests.ps1'
        )

        if ($ChangedFiles.Count -gt 0) {
            $ChangedFileLeafNames = $ChangedFiles | ForEach-Object { Split-Path $_ -Leaf }
            $TestFiles = $TestFiles | Where-Object {
                $SourceFileName = '{0}.ps1' -f ($_.BaseName -replace '\.Tests$', '')
                $_.Name -in $AlwaysRunTestFile -or $_.FullName -in $ChangedFiles -or $ChangedFileLeafNames -contains $SourceFileName
            }
            if (($TestFiles | Measure-Object).Count -eq 0) {
                "No Pester tests relevant to the changed files were found. Skipping test run." | Write-Host
                return
            }
        }

        $PesterConfig = New-PesterConfiguration
        $PesterConfig.Run.Path = $TestFiles.FullName
        $PesterConfig.Run.Exit = $false
        $PesterConfig.Run.PassThru = $true
        $PesterConfig.TestResult.Enabled = $true
        $PesterConfig.TestResult.OutputFormat = 'JUnitXml'
        $PesterConfig.TestResult.OutputPath = (Join-Path $ParentPath -ChildPath 'buildoutput\TestResults.xml')
        $PesterConfig.Output.Verbosity = 'Detailed'

        $Result = Invoke-Pester -Configuration $PesterConfig

        if ($Result.FailedCount -gt 0) {
            Write-Error -Message ('{0} Pester test(s) failed. Build cannot continue!' -f $Result.FailedCount) -ErrorAction Stop
        }
    }
    catch {
        throw
    }
}

Task Dependencies {
    try {
        # Fetches the pinned WebView2 SDK and lays the four assemblies out in the package, so a normal
        # module import makes no network call at all. Every byte is hash-verified: the package before
        # it is opened, then each extracted file against its own pin in src\DependencyLock.psd1.
        #
        # This deliberately writes into buildoutput and never into src\. .gitignore only excludes
        # src/bin/Debug/**, so a stray src\bin\*.dll would be committable and would fail the
        # "No redistributable binaries" test in tests\ThirdPartyNotices.Tests.ps1.
        "Bundle pinned dependencies" | Write-Host
        & "$PSScriptRoot\Get-BundledDependency.ps1" -ArtifactId "Microsoft.Web.WebView2" -OutputPath $BundleDir
    }
    catch {
        throw $_
        exit 1
    }
}

Task Build -Depends Test, Dependencies, TestAssemblies {
    try {
        $FormattingSettings = @{
            IncludeRules = @("PSPlaceOpenBrace", "PSUseConsistentIndentation", "PsAvoidUsingCmdletAliases", "PSUseConsistentWhitespace", "PSAlignAssignmentStatement", "PSPlaceCloseBrace")
            Rules        = @{
                PSPlaceOpenBrace           = @{
                    Enable             = $true
                    OnSameLine         = $true
                    NewLineAfter       = $true
                    IgnoreOneLineBlock = $true
                }
                PSUseConsistentIndentation = @{
                    Enable = $true
                }
                PsAvoidUsingCmdletAliases  = @{
                    Enable = $true
                }
                PSUseConsistentWhitespace  = @{
                    Enable                                  = $false
                    CheckInnerBrace                         = $true
                    CheckOpenBrace                          = $false
                    CheckOpenParen                          = $false
                    CheckOperator                           = $true
                    CheckPipe                               = $true
                    CheckPipeForRedundantWhitespace         = $false
                    CheckSeparator                          = $true
                    CheckParameter                          = $true
                    IgnoreAssignmentOperatorInsideHashTable = $false
                }
                PSAlignAssignmentStatement = @{
                    Enable         = $true
                    CheckHashtable = $true
                }
                PSPlaceCloseBrace          = @{
                    Enable             = $true
                    NoEmptyLineBefore  = $false
                    IgnoreOneLineBlock = $true
                    NewLineAfter       = $true
                }
            }
        }

        function New-HeaderRow {
            param(
                [string]$Text,
                [int]$Length = 100,
                [char]$BeginChar = "#",
                [char]$FillChar = " ",
                [char]$EndChar = "#"
            )
            $HeaderRow = $null
            $HeaderRow = "{0}{1}" -f $BeginChar, $FillChar
            $HeaderRow += $Text

            do {
                $HeaderRow += $FillChar
            }
            until ($HeaderRow.Length -gt ($Length - 1))
            $HeaderRow += "{0}`n" -f $EndChar
            return $HeaderRow

        }
        $ModulePsd1 = Import-PowerShellDataFile (Join-Path $ModuleSource -ChildPath ("{0}.psd1" -f $ModuleName))
        $ModulePsd1.CmdletsToExport = @()
        $ModulePsd1.AliasesToExport = @()

        try {
            $CurrentModulePsd1 = Import-PowerShellDataFile (Join-Path -Path $OutputDir -ChildPath ("{0}.psd1" -f $ModuleName))
        }
        catch {
            $CurrentModulePsd1 = $null
        }

        if (![String]::IsNullOrWhiteSpace($Version)) {
            [version]$NewVersion = "{0}" -f $Version
        }
        else {
            [version]$NewVersion = $Date.ToString('yyyy.MM.dd.001')
            if ($CurrentModulePsd1) {
                [version]$CurrentModuleVersion = $CurrentModulePsd1.ModuleVersion
                if ($CurrentModuleVersion -ge $NewVersion) {
                    $NewVersion = [version]$CurrentModuleVersion
                    $NewVersion = New-Object System.Version($NewVersion.Major, $NewVersion.Minor, $NewVersion.Build, ($NewVersion.Revision + 1))
                }
            }
        }

        $ModulePsd1.ModuleVersion = $NewVersion

        #Work-around for the bug in New-ModuleManifest that breaks the PrivateData key (Source: https://github.com/PowerShell/PowerShell/issues/5922)
        $PrivateData = $ModulePsd1.PrivateData | ConvertTo-Json | ConvertFrom-Json -AsHashtable
        $ModulePsd1.Remove("PrivateData")

        $SerializedContent = $PrivateData.GetEnumerator() | ForEach-Object {
            if ($_ -is [System.Collections.DictionaryEntry]) {
                $String = "$($_.Key) = @{"
                if ($_.Value -is [System.Collections.Hashtable]) {
                    # Serialize nested hashtables into a string
                    $_.Value.GetEnumerator() | ForEach-Object {
                        $String += "`n"
                        if (($_.Value | Measure-Object).Count -gt 1) {
                            $String += "{0} = @({1})" -f $_.Key, (($_.Value | ForEach-Object { "`"{0}`"" -f $_ }) -join ",")
                        }
                        else {
                            $String += "{0} = `"{1}`"" -f $($_.Key) , $($_.Value)
                        }
                    }
                    return $String
                }
            }
        }

        $ModulePsd1Path = (Join-Path $OutputDir -ChildPath ("{0}.psd1" -f $ModuleName))
        New-ModuleManifest -Path $ModulePsd1Path @ModulePsd1
        (Get-Content -Path $ModulePsd1Path) -replace 'PSData = @{', $SerializedContent | Set-Content -Path $ModulePsd1Path -Encoding UTF8 -Force

        #    New-ModuleManifest @Modulepsd1
        "Module psd1 output file: {0}" -f $($ModulePsd1Path) | Write-Host
        (Get-Content $($ModulePsd1Path) -Raw) -replace "`r?`n", "`r`n" | Invoke-Formatter -Settings $FormattingSettings | Set-Content -Path $($ModulePsd1Path) -Encoding UTF8 -Force

        $LatestOmadaWebPSVersion = Get-GalleryModuleVersion -ModuleName "OmadaWeb.PS"

        $Length = 150
        $HeaderContent = $null
        $HeaderContent = New-HeaderRow -Text "" -Length $Length -FillChar "#"
        $HeaderContent += New-HeaderRow -Text  "WARNING: DO NOT EDIT THIS FILE AS IT IS GENERATED AND WILL BE OVERWRITTEN ON THE NEXT UPDATE!" -Length $Length -FillChar " "
        $HeaderContent += New-HeaderRow -Text  "" -Length $Length -FillChar " "
        $HeaderContent += New-HeaderRow -Text  ('Generated via psake on: {0}' -f $Date.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")) -Length $Length -FillChar " "
        $HeaderContent += New-HeaderRow -Text  ("Version: {0}" -f $NewVersion.ToString()) -Length $Length -FillChar " "
        $HeaderContent += New-HeaderRow -Text  ("Copyright Fortigi (C) 2024-{0}" -f $Date.ToString("yyyy")) -Length $Length -FillChar " "
        $HeaderContent += New-HeaderRow -Text  "" -Length $Length -FillChar "#"
        $HeaderContent += "`n"
        $HeaderContent += "`n"
        $HeaderContent += '#requires -Version 7.0'
        $HeaderContent += "`n"

        $OutputDirFile = Join-Path -Path $OutputDir -ChildPath ("{0}.psm1" -f $ModuleName)

        $ModuleFileContent = Get-Content -Path "$ModuleSource\OmadaSqlTroubleShooter.psm1" -Encoding UTF8 -ErrorAction Stop
        $ModuleFileContent = $ModuleFileContent | Where-Object { $_ -notmatch '^\s*#requires' -and $_ -notmatch '^\s*#' }

        #Work-around for enforcing minimum version
        $ModuleFileContent = $ModuleFileContent -replace "\`$MinimumOmadaWebPSVersion\s*=\s*`"0.0`"", ("`$MinimumOmadaWebPSVersion = `"{0}`"" -f $LatestOmadaWebPSVersion)

        #Set Module Version
        if (![String]::IsNullOrWhiteSpace($Version)) {
            $ModuleFileContent = $ModuleFileContent -replace "\`$Script:ModuleVersion\s*=\s*`"Development`"", ("`$Script:ModuleVersion = `"{0}`"" -f $Version)
        }




        $ModuleFileContent = ($ModuleFileContent | Out-String).Trim()

        #$ModuleFileContent = $ModuleFileContent -replace "\`$Private.*-Recurse\)", "`$Private = @()"
        #$ModuleFileContent = $ModuleFileContent -replace "^\`$Public.*", "`$Public = `@(Get-ChildItem -Path `"`$PSScriptRoot\Lib\Functions\Functions.ps1`" -Recurse)"


        $ModuleContent = $HeaderContent, $ModuleFileContent -join "`r`n"

        $ModuleContent = $ModuleContent -replace "`r?`n", "`r`n" | Invoke-Formatter -Settings $FormattingSettings
        "Module psm1 output file: {0}" -f $OutputDirFile | Write-Host
        $ModuleContent | Out-File -Path $OutputDirFile -Encoding UTF8 -Force

        "Copy nuspec file" | Write-Host
        Copy-Item -Path "$ParentPath\OmadaSqlTroubleShooter.nuspec" -Destination "$OutputDir" -Force

        # Ship the licence and the third-party notices with the module. The MIT licence of the
        # bundled Monaco editor requires its copyright notice to travel with the redistribution,
        # so THIRD-PARTY-NOTICES.md must be part of every published package, not just the repo.
        "Copy licence and third-party notices" | Write-Host
        "LICENSE", "THIRD-PARTY-NOTICES.md", "README.md", "SECURITY.md" | ForEach-Object {
            $NoticeSourcePath = Join-Path $ParentPath -ChildPath $_
            if (-not (Test-Path $NoticeSourcePath -PathType Leaf)) {
                "Required file '{0}' was not found at '{1}'" -f $_, $NoticeSourcePath | Write-Error -ErrorAction Stop
            }
            Copy-Item -Path $NoticeSourcePath -Destination $OutputDir -Force
        }

        # The dependency lock has to sit next to the psm1 in the package: the module resolves it
        # through $PSScriptRoot and refuses every download without it, so a package missing this file
        # cannot start. The post-condition below is what stands in for a FileList entry in the psd1 -
        # see DependencyLock.Tests.ps1 for why FileList is deliberately not used.
        "Copy dependency lock" | Write-Host
        Copy-Item -Path (Join-Path $ModuleSource -ChildPath "DependencyLock.psd1") -Destination $OutputDir -Force
        $LockOutputPath = Join-Path $OutputDir -ChildPath "DependencyLock.psd1"
        if (-not (Test-Path $LockOutputPath -PathType Leaf)) {
            "The dependency lock was not copied to '{0}'. The published module would refuse every download." -f $OutputDir | Write-Error -ErrorAction Stop
        }

        "Copy lib contents" | Write-Host

        Get-Item -Path (Join-Path $ModuleSource -ChildPath "Monaco") | Copy-Item -Destination $OutputDir -Force -Recurse
        New-Item (Join-Path $OutputDir -ChildPath  "lib\ui") -ItemType Directory -Force | Out-Null
        New-Item (Join-Path $ModuleSource -ChildPath  "lib\ui") -ItemType Directory -Force | Out-Null
        Get-ChildItem -Path (Join-Path $ModuleSource -ChildPath "lib\ui") -Filter *.xaml | Where-Object { $_.BaseName -notlike "_*" } | Copy-Item -Destination (Join-Path $OutputDir -ChildPath "lib\ui") -Force -Recurse
        New-Item (Join-Path $OutputDir -ChildPath  "lib\ui\icons") -ItemType Directory -Force | Out-Null
        New-Item (Join-Path $ModuleSource -ChildPath  "lib\ui\icons") -ItemType Directory -Force | Out-Null
        Get-ChildItem -Path (Join-Path $ModuleSource -ChildPath "lib\ui\icons") -Filter *.ico | Where-Object { $_.BaseName -notlike "_*" } | Copy-Item -Destination (Join-Path $OutputDir -ChildPath "lib\ui\icons") -Force -Recurse
        New-Item (Join-Path $OutputDir -ChildPath  "lib\ui\images") -ItemType Directory -Force | Out-Null
        New-Item (Join-Path $ModuleSource -ChildPath  "lib\ui\images") -ItemType Directory -Force | Out-Null
        Get-ChildItem -Path (Join-Path $ModuleSource -ChildPath "lib\ui\images") -Filter *.png | Where-Object { $_.BaseName -notlike "_*" } | Copy-Item -Destination (Join-Path $OutputDir -ChildPath "lib\ui\images") -Force -Recurse

        New-Item (Join-Path $OutputDir -ChildPath  "lib\schema") -ItemType Directory -Force | Out-Null
        Get-ChildItem -Path (Join-Path $ModuleSource -ChildPath "lib\schema") -Filter *.json | Where-Object { $_.BaseName -notlike "_*" } | Copy-Item -Destination (Join-Path $OutputDir -ChildPath "lib\schema") -Force -Recurse


        $LibSource = "functions"
        $SourceChildPath = "lib\{0}" -f $LibSource
        $TargetChildPath = "lib\{0}" -f $LibSource
        $TargetFilePath = "{0}\{1}.ps1" -f $TargetChildPath, $LibSource
        New-Item (Join-Path $OutputDir -ChildPath $TargetChildPath) -ItemType Directory -Force | Out-Null
        Get-ChildItem -Path (Join-Path $OutputDir -ChildPath $TargetChildPath) -Recurse -File | ForEach-Object {
            Get-Item $_ | Remove-Item -Force
        }
        $HeaderContent | Out-File -Path (Join-Path $OutputDir -ChildPath $TargetFilePath) -Force -Append -Encoding utf8
        Get-ChildItem -Path (Join-Path $ModuleSource -ChildPath $SourceChildPath) -Recurse -File | Where-Object { $_.Name -notlike "_*.ps1" } | ForEach-Object {
            $Content = Get-Content $_ -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*#requires' -and $_ -notmatch '^\s*#(?!>)' }
            if (($content | Select-String -SimpleMatch "Wait-Debugger" -AllMatches | Measure-Object).Count -gt 0) {
                "Use of 'Wait-Debugger' command found in script:{0}. This must be removed before building the module" -f $_.Name | Write-Error -ErrorAction Stop
            }
            $Content.Trim() | Out-File -Path (Join-Path $OutputDir -ChildPath $TargetFilePath) -Force -Append -Encoding utf8
        }
        (Get-Content (Join-Path $OutputDir -ChildPath $TargetFilePath) -Raw) -replace "(\r?\n\s*){3,}", "`r`n" -replace "`r?`n", "`r`n" | Invoke-Formatter -Settings $FormattingSettings | Set-Content -Path (Join-Path $OutputDir -ChildPath $TargetFilePath) -Encoding UTF8 -Force

        $LibSource = "events"
        $SourceChildPath = "lib\{0}" -f $LibSource
        $TargetChildPath = "lib\{0}" -f $LibSource

        $EventFiles = Get-ChildItem -Path (Join-Path $ModuleSource -ChildPath $SourceChildPath) -Recurse -File | Where-Object { $_.Name -notlike "_*.ps1" }
        $EventFileGroups = $EventFiles | Select-Object *, @{Name = "ClassName"; Expression = { ($_.BaseName -split '\.')[0] } } | Group-Object -Property ClassName
        foreach ($EventFileGroupName in $EventFileGroups.Name) {
            $EventFileGroup = $EventFileGroups | Where-Object { $_.Name -eq $EventFileGroupName }
            $TargetFilePath = "{0}\{1}.ps1" -f $TargetChildPath, $EventFileGroupName
            New-Item (Join-Path $OutputDir -ChildPath $TargetChildPath) -ItemType Directory -Force | Out-Null
            Get-ChildItem -Path (Join-Path $OutputDir -ChildPath $TargetChildPath) -Recurse -File | Where-Object { $_.BaseName -eq $EventFileGroup.Name } | ForEach-Object {
                Get-Item $_ | Remove-Item -Force
            }
            $HeaderContent | Out-File -Path (Join-Path $OutputDir -ChildPath $TargetFilePath) -Force -Append -Encoding utf8
            foreach ($EventFile in $EventFileGroup.Group.FullName) {
                $Content = Get-Content $EventFile -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*#requires' -and $_ -notmatch '^\s*#(?!>)' }
                if (($content | Select-String -SimpleMatch "Wait-Debugger" -AllMatches | Measure-Object).Count -gt 0) {
                    "Use of 'Wait-Debugger' command found in script:{0}. This must be removed before building the module" -f $EventFile.Name | Write-Error -ErrorAction Stop
                }
                $Content.Trim() | Out-File -Path (Join-Path $OutputDir -ChildPath $TargetFilePath) -Force -Append -Encoding utf8
            }
            (Get-Content (Join-Path $OutputDir -ChildPath $TargetFilePath) -Raw) -replace "(\r?\n\s*){3,}", "`r`n" -replace "`r?`n", "`r`n" | Invoke-Formatter -Settings $FormattingSettings | Set-Content -Path (Join-Path $OutputDir -ChildPath $TargetFilePath) -Encoding UTF8 -Force
        }
    }
    catch {
        throw $_
        exit 1
    }
}

Task ImportModule -Depends Build {

    try {
        
        $LatestOmadaWebPSVersion = Get-GalleryModuleVersion -ModuleName "OmadaWeb.PS" -AllowPrerelease:$AllowPrerelease
        $LatestOmadaWebPSVersionStripped = $LatestOmadaWebPSVersion -replace "-nightly\d+", ""

        $OmadaWebPSModulePath = Join-Path $Env:Temp -ChildPath $([guid]::NewGuid().ToString())
        New-Item $OmadaWebPSModulePath -Force -ItemType Directory | Out-Null

        Save-Module -Name "OmadaWeb.PS" -Path $OmadaWebPSModulePath -Force -MinimumVersion $LatestOmadaWebPSVersion -AllowPrerelease:$AllowPrerelease

        "Import OmadaWeb.PS module" | Write-Host
        $OmadaWebPSModuleVersionPath = Join-Path $OmadaWebPSModulePath -ChildPath ("OmadaWeb.PS\{0}\OmadaWeb.PS.psd1" -f $LatestOmadaWebPSVersionStripped)

        Remove-Module -Name "OmadaWeb.PS" -Force -ErrorAction SilentlyContinue
        Import-Module $OmadaWebPSModuleVersionPath -Force

        "Test Import module" | Write-Host
        Test-ModuleManifest -Path "$OutputDir\$ModuleName.psd1"

        $Test = Import-Module "$OutputDir\$ModuleName.psd1" -Force -PassThru
        if ($Test) {
            "Module loaded successfully" | Write-Verbose
            try {
                Remove-Module -Name $Test.Name -Force
            }
            catch {}
            try {
                Remove-Module -Name "OmadaWeb.PS" -Force
            }
            catch {}
        }
        else {
            "Module failed to load" | Write-Error -ErrorAction Stop
            try {
                Remove-Module -Name $Test.Name -Force
            }
            catch {}
        }

        if (![string]::IsNullOrEmpty($OmadaWebPSModulePath) -and (Test-Path $OmadaWebPSModulePath -PathType Container)) {
            Remove-Item -Path $OmadaWebPSModulePath -Recurse -Force
        }
    }
    catch {
        if (![string]::IsNullOrEmpty($OmadaWebPSModulePath) -and (Test-Path $OmadaWebPSModulePath -PathType Container)) {
            Remove-Item -Path $OmadaWebPSModulePath -Recurse -Force
        }
        throw $_
        exit 1
    }
}

# The old TestAssemblies asserted a Bin\WebView2Dlls folder AND a msedgewebview2.exe in the build
# output. Nothing ever produced either - the only task that would have was in no task chain - so it
# could only ever fail, and Part A removed it. It is back here, checking what Task Dependencies
# actually produces.
#
# The msedgewebview2.exe requirement is deliberately not back. That is the WebView2 *Runtime*, a
# 260 MB component this project does not redistribute (see THIRD-PARTY-NOTICES.md section 3.1) and
# never ships into the package. Only the SDK assemblies are bundled.
#
# In the chains directly, not just reachable through Deploy: a package whose bundle is missing or
# corrupt still imports - it degrades to the runtime download - so nothing else would notice.
#
# Build depends on it as well as the chains listing it. That is what covers the nightly, which runs
# a bare "Build" and publishes the result to the PowerShell Gallery; without it the one lane that
# ships nightly packages would be the only one not checking what it ships.
Task TestAssemblies -Depends Dependencies {
    try {
        "Verify bundled assemblies" | Write-Host

        if (-not (Test-Path $BundleDir -PathType Container)) {
            "The bundle folder '{0}' does not exist. Task Dependencies did not run." -f $BundleDir | Write-Error -ErrorAction Stop
        }

        $Lock = Import-PowerShellDataFile -Path (Join-Path $ModuleSource -ChildPath "DependencyLock.psd1")
        $Artifact = @($Lock.Artifacts | Where-Object { $_.Id -eq "Microsoft.Web.WebView2" })[0]

        foreach ($File in @($Artifact.Files)) {
            $FilePath = Join-Path $BundleDir -ChildPath $File.Target
            if (-not (Test-Path $FilePath -PathType Leaf)) {
                "The bundled assembly '{0}' is missing from '{1}'." -f $File.Target, $BundleDir | Write-Error -ErrorAction Stop
            }

            $ActualSha256 = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($ActualSha256 -ne $File.Sha256) {
                "The bundled assembly '{0}' does not match its pin.`r`n  Expected: {1}`r`n  Actual:   {2}" -f $File.Target, $File.Sha256, $ActualSha256 | Write-Error -ErrorAction Stop
            }

            "  {0} OK" -f $File.Target | Write-Host
        }

        # Without a stamp at the pinned version Test-WebView2Bundle refuses the bundle, and every
        # install would silently fall back to downloading - the bundle would be dead weight.
        $StampPath = Join-Path $BundleDir -ChildPath "WebView2.pin"
        if (-not (Test-Path $StampPath -PathType Leaf)) {
            "The bundle at '{0}' has no WebView2.pin stamp, so the module would ignore it and download instead." -f $BundleDir | Write-Error -ErrorAction Stop
        }

        $Stamp = Import-PowerShellDataFile -Path $StampPath
        if ($Stamp.Version -ne $Artifact.Version) {
            "The bundle stamp records version '{0}' but the lock pins '{1}'." -f $Stamp.Version, $Artifact.Version | Write-Error -ErrorAction Stop
        }

        $BundleSize = (Get-ChildItem -Path $BundleDir -File | Measure-Object -Property Length -Sum).Sum
        "  Stamp OK, pinned version {0}" -f $Artifact.Version | Write-Host
        "  Bundle adds {0:N0} bytes ({1:N2} MB) to the package" -f $BundleSize, ($BundleSize / 1MB) | Write-Host
    }
    catch {
        throw $_
        exit 1
    }
}

Task Deploy -Depends Build, TestAssemblies {

}
