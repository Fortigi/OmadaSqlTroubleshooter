#requires -Version 7.0

[CmdLetBinding()]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'WebViewInstalled', Justification = 'The variable is used, but script analyzer does not recognize it')]
param()

try {
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:Tracer::AutoFlush = $true

    $ModuleName = "OmadaSqlTroubleshooter"
    "Loading {0} Module" -f $ModuleName | Write-Verbose

    $Script:ModuleVersion = "Development"
    $MinimumOmadaWebPSVersion = "2026.07.09.9"
    if ($MinimumOmadaWebPSVersion -ne "0.0") {
        Import-Module OmadaWeb.PS -MinimumVersion $MinimumOmadaWebPSVersion -ErrorAction Stop
        if ((Get-Module -Name OmadaWeb.PS).Version -lt [version]$MinimumOmadaWebPSVersion) {
            throw ("OmadaWeb.PS module version {0} or higher is required." -f $MinimumOmadaWebPSVersion)
        }
    }

    $LocalAppDataPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
    $ModuleAppDataPath = (New-Item (Join-Path $LocalAppDataPath -ChildPath $ModuleName) -ItemType Directory -Force).FullName
    $BinPath = (New-Item (Join-Path $ModuleAppDataPath -ChildPath "Bin\$PowerShellType") -ItemType Directory -Force).FullName

    if (-not (Test-Path "$PSScriptRoot\Lib\Functions\Public" -PathType Container)) {
        $Public = @(Get-ChildItem "$PsscriptRoot\Lib\Functions\Functions.ps1")
    }
    else {
        $Public = @(Get-ChildItem -Path $PSScriptRoot\Lib\Functions\Public\*.ps1 -Recurse | Where-Object { $_.Name -notlike "_*.ps1" })
    }
    if (-not(Test-Path "$PSScriptRoot\Lib\Functions\Private" -PathType Container)) {
        $Private = @()
    }
    else {
        $Private = @(Get-ChildItem -Path $PSScriptRoot\Lib\Functions\Private\*.ps1 -Recurse | Where-Object { $_.Name -notlike "_*.ps1" })
    }
    foreach ($Import in @($Public + $Private)) {
        try {
            . $Import.FullName
        }
        catch {
            "Failed to import function {0}: {1}" -f $($Import.FullName), $_ | Write-Error -ErrorAction "Stop"
        }
    }

    #endregion

    try {
        $WebBinBasePath = New-Item  $BinPath -ItemType Directory -Force
    }
    catch {}

    "{0} - Set paths" -f $MyInvocation.MyCommand | Write-Verbose

    #WebView2 Base Path
    if ($Env:PROCESSOR_ARCHITECTURE -eq "AMD64") {
        $WebView2BasePath = [System.IO.Path]::Combine($WebBinBasePath, "win-x64")
    }
    else {
        $WebView2BasePath = [System.IO.Path]::Combine($WebBinBasePath, "win-x86")
    }
    New-Item -ItemType Directory -Path $WebView2BasePath -Force | Out-Null

    #WebView2 Core Location
    $Script:WebView2CorePath = [System.IO.Path]::Combine($WebView2BasePath, "Microsoft.Web.WebView2.Core.dll")
    "{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebView2CorePath | Write-Verbose

    #WebView2 WinForms Location
    $Script:WebView2WinFormsPath = [System.IO.Path]::Combine($WebView2BasePath, "Microsoft.Web.WebView2.WinForms.dll")
    "{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebView2WinFormsPath | Write-Verbose

    #WebView2 WPF Location
    $Script:WebView2WpfPath = [System.IO.Path]::Combine($WebView2BasePath, "Microsoft.Web.WebView2.Wpf.dll")
    "{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebView2WpfPath | Write-Verbose

    #WebView2 Loader Location
    $Script:WebView2LoaderPath = [System.IO.Path]::Combine($WebView2BasePath, "WebView2Loader.dll")
    "{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebView2LoaderPath | Write-Verbose

    #WebView2 User Profile Location
    $Script:WebView2UserProfilePath = [System.IO.Path]::Combine($ModuleAppDataPath, "Edge User Data\OmadaWebView2Profile")
    "{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebView2UserProfilePath | Write-Verbose

    $WebViewInstalled = Install-WebView2 -IncludeWpf
    # (Join-Path $env:ProgramFiles -ChildPath "Microsoft\EdgeWebView"), (Join-Path ${env:ProgramFiles(x86)} -ChildPath "Microsoft\EdgeWebView"), (Join-Path $LocalAppDataPath -ChildPath "$ModuleName\bin\Webview2Runtime"), (Join-Path $PsscriptRoot -ChildPath "bin\Webview2Runtime") | ForEach-Object {
    #     if (Test-Path $_) {
    #         (Get-ChildItem $_ -Filter *.exe -Recurse | Where-Object { $_.Name -eq "msedgewebview2.exe" }) | ForEach-Object {
    #             "A webview installation found at '{0}'" -f (Split-Path $_) | Write-Verbose
    #             $WebViewInstalled = $true
    #         }
    #     }
    # }

    #Set path to the bin folder to be sure that WebView2Loader.dll is found there.
    #$Env:Path += ";$WebView2BasePath"

    if (!$WebViewInstalled) {
        "Cannot start module because the Microsoft Edge Webview2 RunTime was not found. You can download it from: https://developer.microsoft.com/en-us/microsoft-edge/webview2?form=MA13LH#download-section. When you are not able to install it, you can also add the Webview2 Fixed Version binaries to folder {0}" -f (Join-Path $WebBinBasePath -ChildPath "$ModuleName\bin\Webview2Runtime") | Write-Error -ErrorAction "Stop"
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

}
catch {
    throw
}
