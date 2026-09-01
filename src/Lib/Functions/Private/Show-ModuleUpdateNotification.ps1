function Show-ModuleUpdateNotification {
    <#
        .SYNOPSIS
        Warns the user when a newer stable release of the module is published on the PowerShell Gallery.

        .DESCRIPTION
        Runs at module import. Every reason to skip the check is reported as a single verbose
        line: an empty catch used to hide the failure, which silently disabled the update
        notification for as long as a nightly was the most recently published package.
    #>
    [CmdletBinding()]
    param(
        [string]$ModuleName
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        $InstalledModule = Get-InstalledModuleInfo -ModuleName $ModuleName

        if (-not $InstalledModule) {
            "Could not determine the installed version of '{0}'. Skipping the version check." -f $ModuleName | Write-Verbose
            return
        }

        if (-not $InstalledModule.RepositorySource -or $InstalledModule.RepositorySource -notlike "*powershellgallery.com*") {
            "Module '{0}' was not sourced from the PowerShell Gallery. Skipping version check." -f $ModuleName | Write-Verbose
            return
        }

        $GalleryVersion = Get-GalleryModuleVersion -ModuleName $ModuleName

        if (-not $GalleryVersion) {
            "Could not determine the latest published version of '{0}' on the PowerShell Gallery. Skipping the version check." -f $ModuleName | Write-Verbose
            return
        }

        $VersionComparison = Compare-ModuleVersion -InstalledVersion $InstalledModule.Version -GalleryVersion $GalleryVersion

        if ($null -eq $VersionComparison) {
            "Could not compare the installed version '{0}' of '{1}' with the gallery version '{2}'. Skipping the version check." -f $($InstalledModule.Version), $ModuleName, $GalleryVersion | Write-Verbose
            return
        }

        if ($VersionComparison -lt 0) {
            "The installed version {0} of '{1}' is outdated. Latest version: {2}. Execute Update-Module {1} to update to the latest version!" -f $($InstalledModule.Version), $ModuleName, $GalleryVersion | Write-Warning
        }
        elseif ($VersionComparison -eq 0) {
            "The installed version {0} of '{1}' is up-to-date." -f $($InstalledModule.Version), $ModuleName | Write-Verbose
        }
        else {
            "The installed version {0} of '{1}' is newer than the gallery version {2}." -f $($InstalledModule.Version), $ModuleName, $GalleryVersion | Write-Warning
        }
    }
    catch {
        "The version check for '{0}' could not be completed: {1}" -f $ModuleName, $_.Exception.Message | Write-Verbose
    }
}
