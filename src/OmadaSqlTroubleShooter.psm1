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

    # Pinned versions and expected SHA-256 hashes of every binary the module downloads. Resolved from
    # $PSScriptRoot so it works identically from src\ and from the built module folder. Nothing is
    # downloaded without it - see Get-DependencyLock.
    $Script:DependencyLockPath = Join-Path $PSScriptRoot -ChildPath "DependencyLock.psd1"

    $LocalAppDataPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
    $Script:ModuleAppDataPath = (New-Item (Join-Path $LocalAppDataPath -ChildPath $ModuleName) -ItemType Directory -Force).FullName
    $BinPath = (New-Item (Join-Path $Script:ModuleAppDataPath -ChildPath "Bin") -ItemType Directory -Force).FullName

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

    # WebView2 assembly locations. Prefers the bundle laid down and hash-verified at build time in
    # <ModuleRoot>\Bin\WebView2Dlls\win-x64; falls back to the writable
    # %LOCALAPPDATA%\OmadaSqlTroubleshooter\Bin\<win-x64|win-x86> download path, unchanged. With a
    # valid bundle nothing is downloaded and module import makes no network call at all.
    $ResolvedWebView2Path = Resolve-WebView2AssemblyPath -ModuleRoot $PSScriptRoot -BinPath $WebBinBasePath

    $Script:WebView2CorePath = $ResolvedWebView2Path.Core
    $Script:WebView2WinFormsPath = $ResolvedWebView2Path.WinForms
    $Script:WebView2WpfPath = $ResolvedWebView2Path.Wpf
    $Script:WebView2LoaderPath = $ResolvedWebView2Path.Loader

    # Which of the two folders the paths above point at. Get-WebView2ExpectedHash reads it to decide
    # whether the load-time check compares against the lock or against the download stamp.
    $Script:WebView2Source = $ResolvedWebView2Path.Source

    # Named in the load-time integrity error, so the message says which folder the rejected bytes
    # were in rather than just which file.
    $Script:WebView2BasePath = $ResolvedWebView2Path.BasePath

    "{0} - WebView2 assemblies resolved from the {1} at '{2}'" -f $MyInvocation.MyCommand, $ResolvedWebView2Path.Source.ToLowerInvariant(), $ResolvedWebView2Path.BasePath | Write-Verbose

    # The pin stamp Install-WebView2 writes always lives with the DOWNLOADED assemblies, never in the
    # bundle. Write-WebView2Stamp, Test-WebView2RuntimeVersion and
    # Clear-OmadaSqlTroubleshooterCache -Scope Binaries all address that one, and the module folder
    # is typically read-only anyway. The bundle carries its own stamp, which Test-WebView2Bundle
    # reads directly.
    if ($Env:PROCESSOR_ARCHITECTURE -eq "AMD64") {
        $WebView2DownloadPath = [System.IO.Path]::Combine($WebBinBasePath, "win-x64")
    }
    else {
        $WebView2DownloadPath = [System.IO.Path]::Combine($WebBinBasePath, "win-x86")
    }
    $Script:WebView2StampPath = [System.IO.Path]::Combine($WebView2DownloadPath, "WebView2.pin")

    if ($ResolvedWebView2Path.RequiresInstall) {
        # Only created when it is actually going to be used, so a bundled install does not leave an
        # empty folder behind in the user's profile.
        New-Item -ItemType Directory -Path $WebView2DownloadPath -Force | Out-Null
    }

    #ScriptDom Location - the T-SQL parser behind the editor's client-side syntax diagnostics.
    #Architecture-neutral (pure managed assembly), so it sits in Bin rather than the win-x64/x86
    #subfolder. Only the PATHS are resolved here: unlike WebView2 this dependency is optional, so it
    #is downloaded and loaded from Initialize-OmadaSqlTroubleShooter, where a failure can be reported
    #once and the feature switched off instead of stopping the import.
    $Script:ScriptDomPath = [System.IO.Path]::Combine($WebBinBasePath, "Microsoft.SqlServer.TransactSql.ScriptDom.dll")
    "{0} - {1}" -f $MyInvocation.MyCommand, $Script:ScriptDomPath | Write-Verbose

    #ScriptDom Pin Stamp Location - records which pinned version the installed assembly came from
    $Script:ScriptDomStampPath = [System.IO.Path]::Combine($WebBinBasePath, "ScriptDom.pin")
    "{0} - {1}" -f $MyInvocation.MyCommand, $Script:ScriptDomStampPath | Write-Verbose

    #WebView2 User Profile Base Location
    $Script:WebView2UserProfileBasePath = [System.IO.Path]::Combine($Script:ModuleAppDataPath, "Edge User Data")

    #WebView2 User Profile Location
    $Script:WebView2UserProfilePath = [System.IO.Path]::Combine($Script:ModuleAppDataPath, "Edge User Data\OmadaWebView2Profile")
    "{0} - {1}" -f $MyInvocation.MyCommand, $Script:WebView2UserProfilePath | Write-Verbose

    # Only downloads when there is no usable bundle. Install-WebView2 is unchanged: it fetches the
    # pinned URL, verifies the bytes, and writes the assemblies and their stamp into
    # %LOCALAPPDATA%\OmadaSqlTroubleshooter\Bin, exactly as before.
    if ($ResolvedWebView2Path.RequiresInstall) {
        $WebViewInstalled = Install-WebView2 -IncludeWpf
    }
    else {
        $WebViewInstalled = $true
    }
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
    Show-ModuleUpdateNotification -ModuleName $ModuleName

    #Check shortcuts
    Test-Shortcut

    # Export all the functions
    #Export-ModuleMember -Function @("Invoke-$ModuleName" , "Set-$ModuleNameShortcut")

}
catch {
    throw
}
