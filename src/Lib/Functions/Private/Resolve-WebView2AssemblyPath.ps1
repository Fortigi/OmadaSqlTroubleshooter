function Resolve-WebView2AssemblyPath {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true)]
        [string]$ModuleRoot,
        [parameter(Mandatory = $true)]
        [string]$BinPath,
        [parameter(Mandatory = $false)]
        [string]$ProcessorArchitecture = $Env:PROCESSOR_ARCHITECTURE
    )

    # Decides which folder the WebView2 assemblies are loaded from, and returns the four paths plus
    # whether Install-WebView2 still has to run.
    #
    # Bundle first: <ModuleRoot>\Bin\WebView2Dlls\win-x64, laid down and hash-verified at build time
    # by build\Get-BundledDependency.ps1. With a valid bundle module import makes no network call at
    # all, which is the point - restricted corporate networks are the norm for Omada customers and
    # the module previously could not start without egress to nuget.org.
    #
    # The bundle is used IN PLACE. Nothing is copied out of it. The module folder is typically
    # read-only, which is fine for LoadFrom and is exactly why the writable %LOCALAPPDATA% path has
    # to stay for the fallback.
    #
    # Otherwise the existing %LOCALAPPDATA%\OmadaSqlTroubleshooter\Bin\<win-x64|win-x86> paths are
    # returned unchanged, with RequiresInstall set, and the download path behaves exactly as before.
    #
    # No tracer preamble and no Write-LogOutput here: see Get-DependencyLock. This runs during module
    # import, before Invoke-OmadaSqlTroubleshooter populates $Script:RunTimeConfig.

    # Only x64 is bundled. The manifest declares ProcessorArchitecture = 'Amd64', and neither of the
    # two fetchers this repository used to have ever targeted x86, so x86 always downloads.
    $RuntimeFolder = "win-x64"
    if ($ProcessorArchitecture -ne "AMD64") {
        $RuntimeFolder = "win-x86"
    }

    $DownloadPath = [System.IO.Path]::Combine($BinPath, $RuntimeFolder)

    $Resolved = @{
        Core            = [System.IO.Path]::Combine($DownloadPath, "Microsoft.Web.WebView2.Core.dll")
        WinForms        = [System.IO.Path]::Combine($DownloadPath, "Microsoft.Web.WebView2.WinForms.dll")
        Wpf             = [System.IO.Path]::Combine($DownloadPath, "Microsoft.Web.WebView2.Wpf.dll")
        Loader          = [System.IO.Path]::Combine($DownloadPath, "WebView2Loader.dll")
        BasePath        = $DownloadPath
        Source          = "Download"
        RequiresInstall = $true
    }

    if ($RuntimeFolder -ne "win-x64") {
        "{0} - Architecture '{1}' is not bundled; the assemblies will be downloaded and verified" -f $MyInvocation.MyCommand, $ProcessorArchitecture | Write-Verbose
        return $Resolved
    }

    $BundlePath = [System.IO.Path]::Combine($ModuleRoot, "Bin", "WebView2Dlls", "win-x64")

    if (-not (Test-WebView2Bundle -BundlePath $BundlePath)) {
        "{0} - No usable bundle at '{1}'; the assemblies will be downloaded and verified" -f $MyInvocation.MyCommand, $BundlePath | Write-Verbose
        return $Resolved
    }

    "{0} - Using the bundled WebView2 assemblies in '{1}'" -f $MyInvocation.MyCommand, $BundlePath | Write-Verbose

    return @{
        Core            = [System.IO.Path]::Combine($BundlePath, "Microsoft.Web.WebView2.Core.dll")
        WinForms        = [System.IO.Path]::Combine($BundlePath, "Microsoft.Web.WebView2.WinForms.dll")
        Wpf             = [System.IO.Path]::Combine($BundlePath, "Microsoft.Web.WebView2.Wpf.dll")
        Loader          = [System.IO.Path]::Combine($BundlePath, "WebView2Loader.dll")
        BasePath        = $BundlePath
        Source          = "Bundle"
        RequiresInstall = $false
    }
}
