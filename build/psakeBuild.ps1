Properties {
    $Version = $BuildVersion
    $Date = Get-Date
    $ModuleName = "OmadaSqlTroubleShooter"
    $ParentPath = (Get-Item -Path $PSScriptRoot -Verbose:$false).Parent.FullName
    $ModuleSource = Join-Path -Path $ParentPath -ChildPath 'src'
    $TestSource = Join-Path -Path $ParentPath -ChildPath 'tests'
    $OutputDir = Join-Path -Path $ParentPath -ChildPath 'buildoutput\OmadaSqlTroubleShooter'
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}


Task default -depends Analyze, Test, Build, ImportModule
Task DeployOnly -depends Build, Deploy

Task Analyze {

    $Profile = @{
        Severity     = @('Error', 'Warning')
        IncludeRules = '*'
        ExcludeRules = '*WriteHost', '*AvoidUsingEmptyCatchBlock*', '*UseShouldProcessForStateChangingFunctions*', '*AvoidOverwritingBuiltInCmdlets*', '*UseToExportFieldsInManifest*', '*UseProcessBlockForPipelineCommand*', '*ConvertToSecureStringWithPlainText*', '*UseSingularNouns*'
    }
    $saResults = Invoke-ScriptAnalyzer -Path $ModuleSource -Severity @('Error', 'Warning') -Recurse -Profile $Profile -Verbose:$false
    if ($saResults) {
        $saResults | Format-Table
        Write-Error -Message 'One or more Script Analyzer errors/warnings where found. Build cannot continue!' -ErrorAction "Stop"
    }
}

Task Test -depends Analyze {
}

Task Build -depends Test {

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
        PARAM(
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
    $ModulePsd1.FunctionsToExport = $PublicModules


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
            if ($_.Value -is [System.Collections.Hashtable]) {
                # Serialize nested hashtables into a string
                "$($_.Key) = @{`n$($_.Value.GetEnumerator() | ForEach-Object {`"$($_.Key) = `'$($_.Value)`'`n"})"
            }
            else {
                "$($_.Key) = `'$($_.Value)`'"
            }
        }
    }
    $ModulePsd1Path = (Join-Path $OutputDir -ChildPath ("{0}.psd1" -f $ModuleName))
    New-ModuleManifest -Path $ModulePsd1Path @ModulePsd1
    (Get-Content -Path $ModulePsd1Path) -replace 'PSData = @{', $SerializedContent | Set-Content -Path $ModulePsd1Path -Encoding UTF8 -Force

    #    New-ModuleManifest @Modulepsd1
    "Module psd1 output file: {0}" -f $($ModulePsd1Path) | Write-Host
    (Get-Content $($ModulePsd1Path) -Raw) -replace "`r?`n", "`r`n" | Invoke-Formatter -Settings $FormattingSettings | Set-Content -Path $($ModulePsd1Path) -Encoding UTF8 -Force

    $Length = 150
    $HeaderContent = $null
    $HeaderContent = New-HeaderRow -Text "" -Length $Length -FillChar "#"
    $HeaderContent += New-HeaderRow -Text  "WARNING: DO NOT EDIT THIS FILE AS IT IS GENERATED AND WILL BE OVERWRITTEN ON THE NEXT UPDATE!" -Length $Length -FillChar " "
    $HeaderContent += New-HeaderRow -Text  "" -Length $Length -FillChar " "
    $HeaderContent += New-HeaderRow -Text  ('Generated via psake on: {0}' -f $Date.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")) -Length $Length -FillChar " "
    $HeaderContent += New-HeaderRow -Text  ("Version: {0}" -f $NewVersion.ToString()) -Length $Length -FillChar " "
    $HeaderContent += New-HeaderRow -Text  ("Copyright Fortigi (C) {0}" -f $Date.ToString("yyyy")) -Length $Length -FillChar " "
    $HeaderContent += New-HeaderRow -Text  "" -Length $Length -FillChar "#"
    $HeaderContent += "`n`n"

    $OutputDirFile = Join-Path -Path $OutputDir -ChildPath ("{0}.psm1" -f $ModuleName)

    $ModuleFileContent = Get-Content -Path "$ModuleSource\OmadaSqlTroubleShooter.psm1" -Encoding UTF8 -ErrorAction Stop -Raw
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
    Get-ChildItem -Path (Join-Path $ModuleSource -ChildPath "lib\ui") -Filter *.xaml | Copy-Item -Destination (Join-Path $OutputDir -ChildPath "lib\ui") -Force -Recurse
    Get-ChildItem -Path (Join-Path $ModuleSource -ChildPath "lib\ui") -Filter *.ico | Copy-Item -Destination (Join-Path $OutputDir -ChildPath "lib\ui") -Force -Recurse

    New-Item (Join-Path $OutputDir -ChildPath  "lib\schema") -ItemType Directory -Force | Out-Null
    Get-ChildItem -Path (Join-Path $ModuleSource -ChildPath "lib\schema") -Filter *.json | Copy-Item -Destination (Join-Path $OutputDir -ChildPath "lib\schema") -Force -Recurse

    @("functions", "events") | ForEach-Object {
        $LibSource = $_
        $SourceChildPath = "lib\{0}" -f $LibSource
        $TargetChildPath = "lib\{0}" -f $LibSource
        $TargetFilePath = "{0}\{1}.ps1" -f $TargetChildPath, $LibSource
        New-Item (Join-Path $OutputDir -ChildPath $TargetChildPath) -ItemType Directory -Force | Out-Null
        Get-ChildItem -Path (Join-Path $OutputDir -ChildPath $TargetChildPath) -Recurse -File | ForEach-Object {
            Get-Item $_ | Remove-Item -Force
        }
        $HeaderContent | Out-File -Path (Join-Path $OutputDir -ChildPath $TargetFilePath) -Force -Append -Encoding utf8
        Get-ChildItem -Path (Join-Path $ModuleSource -ChildPath $SourceChildPath) -Recurse -File | ForEach-Object {
            $Content = Get-Content $_ -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*#requires' -and $_ -notmatch '^\s*#' }
            $Content.Trim() | Out-File -Path (Join-Path $OutputDir -ChildPath $TargetFilePath) -Force -Append -Encoding utf8
        }
        (Get-Content (Join-Path $OutputDir -ChildPath $TargetFilePath) -Raw) -replace "`r?`n", "`r`n" | Invoke-Formatter -Settings $FormattingSettings | Set-Content -Path (Join-Path $OutputDir -ChildPath $TargetFilePath) -Encoding UTF8 -Force
    }

    New-Item (Join-Path $OutputDir -ChildPath "Bin\Webview2Dlls") -ItemType Directory -Force | Out-Null
    $FilesToCopy = @(
        "runtimes\win-x64\native\WebView2Loader.dll",
        "lib_manual\netcoreapp3.0\Microsoft.Web.WebView2.Core.dll",
        "lib_manual\netcoreapp3.0\Microsoft.Web.WebView2.WinForms.dll",
        "lib_manual\net5.0-windows10.0.17763.0\Microsoft.Web.WebView2.Wpf.dll"
    )
    $DownLoadFiles = $false
    foreach ($File in $FilesToCopy) {
        $File = "bin\Webview2Dlls\{0}" -f $File.Split("\")[-1]
        if (!(Test-Path (Join-Path $OutputDir -ChildPath $File) -PathType Leaf)) {
            $DownLoadFiles = $true
        }
    }

    New-Item (Join-Path $OutputDir -ChildPath "bin\Webview2Runtime") -ItemType Directory -Force | Out-Null

    if ($DownLoadFiles -or $Force) {
        if ($null -eq (Get-PackageSource | Where-Object { $_.Name -eq "NuGet" })) {
            "Package source 'NuGet' not found. You can retry after registering it using this command: 'Register-PackageSource -Name NuGet -Location `"https://api.NuGet.org/v3/index.json`" -ProviderName NuGet'" | Write-Host
            break
        }

        "Get WebView2 from NuGet (this might take a minute or two to complete)" | Write-Host
        $PackageTempFolder = New-Item (Join-Path $env:TEMP -ChildPath "OmadaSqlTroubleShooter") -ItemType Directory -Force
        $WebView2DllsDownloaded = $false

        try {
            $Package = Save-Package Microsoft.Web.WebView2 -minimumVersion 1.0.2903.40 -Path $PackageTempFolder.FullName -Force -Source NuGet
            $WebView2DllsDownloaded = $true
        }
        catch {
            "Failed to download WebView2 Dll files from NuGet. Please get the latest release from https://www.nuget.org/packages/microsoft.web.webview2. The following files need to be copied to '{0}': {1}. Error: {2}" -f (Join-Path $OutputDir -ChildPath "Bin\Webview2Dlls"), $FilesToCopy, $_.Exception.Message | Write-Warning
            $WebView2DllsDownloaded
        }
        if ($WebView2DllsDownloaded) {
            Get-Item (Join-Path $PackageTempFolder.FullName -ChildPath $Package.PackageFilename) | Expand-Archive -DestinationPath $PackageTempFolder.FullName -Force

            foreach ($File in $FilesToCopy) {
                Get-Item (Join-Path $PackageTempFolder.FullName -ChildPath $File) | Copy-Item -Destination (Join-Path $OutputDir -ChildPath "Bin\Webview2Dlls")  -Force
            }
            Get-Item $PackageTempFolder.FullName | Remove-Item -Recurse -Force
        }
    }
}

Task ImportModule -depends Build {

    $Test = Import-Module "$OutputDir\$ModuleName.psd1" -Force -PassThru
    if ($Test) {
        "Module loaded successfully" | Write-Verbose
        Remove-Module -name $Test.Name -Force
    }
    else {
        "Module failed to load" | Write-Error -ErrorAction Stop
    }
}
