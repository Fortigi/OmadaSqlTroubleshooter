function Get-OmadaSqlTroubleshooterCacheItem {
    [CmdletBinding()]
    param(
        [ValidateSet("All", "Binaries", "BrowserProfiles")]
        [string[]]$Scope = "All"
    )

    # Single inventory of the data the module caches on this machine, shared by
    # Clear-OmadaSqlTroubleshooterCache and by anything else that needs to report the footprint.
    #
    # Deliberately excludes the configuration under %APPDATA%\OmadaSqlTroubleshooter\config: saved
    # connections, window positions and preferences are settings the user chose, not cache, and
    # removing them is not something a command called "Clear cache" should do.
    #
    # No tracer preamble: this command is callable without Invoke-OmadaSqlTroubleshooter having run.

    $SelectedScope = if ($Scope -contains "All") {
        @("Binaries", "BrowserProfiles")
    }
    else {
        @($Scope | Select-Object -Unique)
    }

    $Item = [System.Collections.Generic.List[object]]::new()

    if ($SelectedScope -contains "Binaries") {
        $Item.Add((New-OmadaSqlTroubleshooterCacheItem -Scope "Binaries" -Artefact "Downloaded assemblies (WebView2, ScriptDom)" -Path (Join-Path $Script:ModuleAppDataPath -ChildPath "Bin") -Protection "NTFS permissions on the user profile only"))
    }

    if ($SelectedScope -contains "BrowserProfiles") {
        $Item.Add((New-OmadaSqlTroubleshooterCacheItem -Scope "BrowserProfiles" -Artefact "WebView2 Edge user profiles" -Path $Script:WebView2UserProfileBasePath -Protection "NTFS permissions on the user profile only"))
    }

    return $Item.ToArray()
}
