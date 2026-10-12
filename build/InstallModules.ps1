<#
    Installs the build modules pinned in build/BuildModules.psd1, each at exactly its pinned version.

    Run on its own (the workflows do) it only installs. Dot-sourced with -Import (build/build.ps1 does)
    it also imports those exact versions into the session, so psake, the analyzer and the test runner
    can never be a different version from the one this file installed - not even when a newer one is
    already present on the machine.
#>
[CmdletBinding()]
param(
    [switch]$Import
)

try {
    $BuildModuleManifest = Import-PowerShellDataFile -Path (Join-Path -Path $PSScriptRoot -ChildPath 'BuildModules.psd1')

    if ($PSVersionTable.PSVersion -lt [version]$BuildModuleManifest.MinimumPowerShellVersion) {
        throw ("The build needs PowerShell {0} or later; this is {1}." -f $BuildModuleManifest.MinimumPowerShellVersion, $PSVersionTable.PSVersion)
    }

    "Validate Modules" | Write-Host
    foreach ($BuildModule in $BuildModuleManifest.Modules) {
        $Installed = Get-Module -Name $BuildModule.Name -ListAvailable | Where-Object { $_.Version -eq [version]$BuildModule.RequiredVersion }
        if (-not $Installed) {
            "Install {0} {1}" -f $BuildModule.Name, $BuildModule.RequiredVersion | Write-Host
            # -SkipPublisherCheck: Windows ships Pester 3.4.0 signed by a different publisher, and
            # Install-Module refuses to install a newer Pester next to it without this switch.
            Install-Module -Name $BuildModule.Name -RequiredVersion $BuildModule.RequiredVersion -Repository PSGallery -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber
        }
        else {
            "{0} {1} is installed" -f $BuildModule.Name, $BuildModule.RequiredVersion | Write-Host
        }
    }

    if ($Import) {
        foreach ($BuildModule in @($BuildModuleManifest.Modules | Where-Object { $_.Import })) {
            Import-Module -Name $BuildModule.Name -RequiredVersion $BuildModule.RequiredVersion -Force -Global
        }
    }

    "Register NuGet PackageSource" | Write-Host
    Register-PackageSource -Name NuGet -Location "https://api.NuGet.org/v3/index.json" -ProviderName NuGet -Force | Out-Null
}
catch {
    Write-Error "Failed to validate modules: $_"
    exit 1
}
