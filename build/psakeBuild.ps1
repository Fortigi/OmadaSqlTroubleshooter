Properties {
    $Version = $BuildVersion
    $Date = Get-Date
    $ModuleName = "OmadaSqlTroubleShooter"
    $ParentPath = (Get-Item -Path $PSScriptRoot -Verbose:$false).Parent.FullName
    $ModuleSource = Join-Path -Path $ParentPath -ChildPath 'src'
    $TestSource = Join-Path -Path $ParentPath -ChildPath 'tests'
    $OutputDir = Join-Path -Path $ParentPath -ChildPath 'buildoutput\OmadaSqlTroubleShooter'
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null

    # When set (PR validation only), scopes Analyze/Test to just these files so unrelated pre-existing issues don't block unrelated PRs.
    $ChangedFiles = @()
    if ($env:PR_CHANGED_FILES) {
        $ChangedFiles = $env:PR_CHANGED_FILES -split ';' | Where-Object { $_ } | ForEach-Object {
            (Resolve-Path -Path (Join-Path $ParentPath $_) -ErrorAction SilentlyContinue).Path
        } | Where-Object { $_ }
    }
}

Task default -Depends Analyze, Test, Build, ImportModule
Task TestBuildOnly -Depends Analyze, Test, Build
Task Pipeline -Depends Analyze, Test, Build
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
        [string]$ModuleName
    )

    try {
        $ApiEndpoint = "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='{0}'" -f $ModuleName
        $Response = Invoke-RestMethod -Uri $ApiEndpoint -Method Get -Headers @{
            "Accept" = "application/xml"
        } -ConnectionTimeoutSeconds 1

        if ($null -ne $Response) {
            $LatestVersion = $Response | Sort-Object updated -Descending | Select-Object -First 1
            return $LatestVersion.Properties.version
        }
        else {
            return $null
        }
    }
    catch {
        return $null
    }
}

Task Dependencies {
    try {
        "Retrieve dependencies" | Write-Host
        $DestinationFolder = Join-Path $OutputDir -ChildPath "bin"
        & "$PSScriptRoot\RetrieveDependencies.ps1" -DestinationFolder $DestinationFolder -Force
    }
    catch {
        throw $_
        exit 1
    }
}

Task Analyze {

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
        if ($ChangedFiles.Count -gt 0) {
            $ChangedFileLeafNames = $ChangedFiles | ForEach-Object { Split-Path $_ -Leaf }
            $TestFiles = $TestFiles | Where-Object {
                $SourceFileName = '{0}.ps1' -f ($_.BaseName -replace '\.Tests$', '')
                $_.FullName -in $ChangedFiles -or $ChangedFileLeafNames -contains $SourceFileName
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

Task Build -Depends Test {
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

Task TestAssemblies -Depends Build {

    try {

        "Check included assemblies" | Write-Host

        "Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.Wpf.dll" | ForEach-Object {
            "Test assembly: '{0}'" -f $_ | Write-Host
            $WebViewDllPath = Join-Path $OutputDir -ChildPath "Bin\WebView2Dlls\$_"
            if (!(Test-Path $WebViewDllPath -PathType Leaf)) {
                throw ("The WebView2 Dll '{0}' is cannot be found at the '{1}' bin folder!" -f $_, $OutputDir)
            }
        }
        $WebViewLoaderPath = Join-Path $OutputDir -ChildPath "Bin\WebView2Dlls\WebView2Loader.dll"
        "Get 'WebView2Loader.Dll'" | Write-Host
        if (!(Test-Path $WebViewLoaderPath -PathType Leaf)) {
            throw ("The WebView2Loader Dll '{0}' is cannot be found at the '{1}' bin folder!" -f "WebView2Loader.dll", $OutputDir)
        }

        $WebViewRunTimePath = Join-Path $OutputDir -ChildPath "Bin\WebView2Runtime"
        "Check WebViewRunTime" | Write-Host
        if (!(Test-Path $WebViewRunTimePath -PathType Container)) {
            throw ("The WebViewRunTime was not found at the '{0}' bin folder!" -f $OutputDir)
        }
        elseif (!(Test-Path (Join-Path $WebViewRunTimePath -ChildPath "msedgewebview2.exe") -PathType Leaf)) {
            throw ("Msedgewebview2.exe is not found at the '{0}' bin folder!" -f $OutputDir)
        }

    }
    catch {
        throw $_
        exit 1
    }
}


Task ImportModule -Depends Build {

    try {

        $LatestOmadaWebPSVersion = Get-GalleryModuleVersion -ModuleName "OmadaWeb.PS"

        if (!(Get-Module -Name "OmadaWeb.PS" -ListAvailable)) {
            Install-Module -Name "OmadaWeb.PS" -Scope CurrentUser -Force -MinimumVersion $LatestOmadaWebPSVersion
        }
        elseif (Get-Module -Name "OmadaWeb.PS" -ListAvailable -ErrorAction SilentlyContinue | Where-Object { $_.Version -lt $LatestOmadaWebPSVersion }) {
            Update-Module -Name "OmadaWeb.PS" -Scope CurrentUser -Force -RequiredVersion $LatestOmadaWebPSVersion
        }
        "Import OmadaWeb.PS module" | Write-Host
        Import-Module -Name "OmadaWeb.PS" -MinimumVersion $LatestOmadaWebPSVersion -Force

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
    }
    catch {
        throw $_
        exit 1
    }
}

Task Deploy -Depends TestAssemblies {

}
