function Get-AdHocQueryDraft {
    <#
    .SYNOPSIS
        Reads the ad-hoc query drafts kept from earlier sessions.

    .DESCRIPTION
        A draft is an ad-hoc query - SQL typed into a tab with no saved query behind it - that was not
        saved to Omada when the application closed or crashed. Restore-AdHocQueryDraft offers them
        back at the next start.

        Never throws. A missing store is "no drafts". A store that cannot be read or parsed is also
        "no drafts", with a warning: losing a draft is bad, but refusing to start the application
        over a corrupt cache file would be worse, and the file is left in place for inspection until
        the next write replaces it.

        Entries without a tab id or without any text are dropped: there is nothing to restore, and
        nowhere to restore it to.

    .PARAMETER Path
        The draft store. Defaults to Get-AdHocQueryDraftPath.

    .OUTPUTS
        [PSCustomObject[]] @{ TabId; Text; SavedAt; TabConfig }, possibly none.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-AdHocQueryDraftPath)
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    try {
        $Private:Store = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        "The ad-hoc query draft store '{0}' could not be read and is ignored: {1}" -f $Path, $_.Exception.Message | Write-LogOutput -LogType WARNING -SkipDialog
        return
    }

    foreach ($Private:Draft in @($Private:Store.Drafts)) {
        if ($null -eq $Private:Draft -or [string]::IsNullOrWhiteSpace($Private:Draft.TabId) -or [string]::IsNullOrWhiteSpace($Private:Draft.Text)) {
            continue
        }
        $Private:Draft
    }
}
