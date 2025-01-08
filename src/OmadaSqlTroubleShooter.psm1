#requires -Module OmadaWeb.PS
#requires -Version 7.0
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'WebViewInstalled', Justification = 'The variable is used, but script analyzer does not recognize it')]
PARAM()

$ModuleName = "OmadaSqlTroubleshooter"
"Loading {0} Module" -f $ModuleName | Write-Verbose

$LocalAppDataPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
if (-not (Test-Path "$PSScriptRoot\Lib\Functions\Public" -PathType Container)) {
    $Public = @(Get-ChildItem "$PsscriptRoot\Lib\Functions\Functions.ps1")
}
else {
    $Public = @(Get-ChildItem -Path $PSScriptRoot\Lib\Functions\Public\*.ps1 -Recurse)
}
if (-not(Test-Path "$PSScriptRoot\Lib\Functions\Private" -PathType Container)) {
    $Private = @()
}
else {
    $Private = @(Get-ChildItem -Path $PSScriptRoot\Lib\Functions\Private\*.ps1 -Recurse)
}
Foreach ($Import in @($Public + $Private)) {
    try {
        . $Import.FullName
    }
    catch {
        "Failed to import function {0}: {1}" -f $($Import.FullName), $_ | Write-Error -ErrorAction "Stop"
    }
}

$WebViewInstalled = $false
(Join-Path $env:ProgramFiles -ChildPath "Microsoft\EdgeWebView"), (Join-Path ${env:ProgramFiles(x86)} -ChildPath "Microsoft\EdgeWebView"), (Join-Path $LocalAppDataPath -ChildPath "$ModuleName\bin\Webview2Runtime"), (Join-Path $PsscriptRoot -ChildPath "bin\Webview2Runtime") | ForEach-Object {
    if (Test-Path $_) {
        (Get-ChildItem $_ -Filter *.exe -Recurse | Where-Object { $_.Name -eq "msedgewebview2.exe" }) | ForEach-Object {
            "A webview installation found at '{0}'" -f (Split-Path $_) | Write-Verbose
            $WebViewInstalled = $true
        }
    }
}

if (!$WebViewInstalled) {
    "Cannot start module because the Microsoft Edge Webview2 RunTime was not found. You can download it from: https://developer.microsoft.com/en-us/microsoft-edge/webview2?form=MA13LH#download-section. When you are not able to install it, you can also add the Webview2 Fixed Version binaries to folder {0}" -f (Join-Path $LocalAppDataPath -ChildPath "$ModuleName\bin\Webview2Runtime") | Write-Error -ErrorAction "Stop"
}

"Validate version" | Write-Verbose
try {
    $InstalledModule = Get-InstalledModuleInfo -ModuleName $ModuleName

    if (-not $InstalledModule.RepositorySource -or $InstalledModule.RepositorySource -notlike "*powershellgallery.com*") {
        "Module '{0}' was not sourced from the PowerShell Gallery. Skipping version check." -f $ModuleName | Write-Verbose
    }
    else {
        $GalleryVersion = Get-GalleryModuleVersion -ModuleName $ModuleName

        if (-not $GalleryVersion) {
        }
        else {
            if ([version]$InstalledModule.Version -lt [version]$GalleryVersion) {
                "The installed version {0} of '{1}' is outdated. Latest version: {2}. Execute Update-Module {1} to update to the latest version!" -f ($($InstalledModule.Version)), $ModuleName, $GalleryVersion | Write-Warning
            }
            elseif ([version]$InstalledModule.Version -eq [version]$GalleryVersion) {
                "The installed version {0} of '{1}' is up-to-date." -f ($($InstalledModule.Version)) , $ModuleName | Write-Verbose
            }
            else {
                "The installed version {0} of '{1}' is newer than the gallery version {2}." -f ($($InstalledModule.Version)), $ModuleName, $GalleryVersion | Write-Warning
            }
        }
    }

}
catch {}

#Check shortcuts
Test-Shortcut

# Export all the functions
#Export-ModuleMember -Function @("Invoke-$ModuleName" , "Set-$ModuleNameShortcut")
