function Get-AdHocQueryDraftPath {
    <#
    .SYNOPSIS
        Where the ad-hoc query drafts are kept between sessions.

    .DESCRIPTION
        Next to the persisted tab sessions (config\tabs.clixml), under the per-user application data
        folder, so it has the same owner and the same access control as every other file this
        application writes about the user's work. A reset (-Reset, or the ResetRequested flag)
        discards it together with the tab sessions; see Restore-AdHocQueryDraft.

    .PARAMETER AppDataFolder
        The application data folder. Defaults to the one this session runs with.

    .OUTPUTS
        [string] The full path of the draft store. The file need not exist.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$AppDataFolder = $Script:RunTimeConfig.AppDataFolder
    )

    return [System.IO.Path]::Combine($AppDataFolder, "config", "adhoc-query-drafts.json")
}
