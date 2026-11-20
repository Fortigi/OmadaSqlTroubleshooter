function Save-AdHocQueryDraft {
    <#
    .SYNOPSIS
        Keeps one tab's unsaved ad-hoc query in the draft store, replacing any earlier draft of it.

    .DESCRIPTION
        One draft per tab, keyed by the tab id. The tab id is also what Save-TabSessions persists, so
        a draft written by a session that closed normally is matched back to its own tab at the next
        start. After a crash tabs.clixml is not rewritten (it is only written while closing), so the
        draft also carries the tab's connection settings - without the password - and
        Restore-AdHocQueryDraft opens a tab from them when no restored tab has that id.

        Not traced: the parameters hold the query text, and the tracer would write it out.

    .PARAMETER TabId
        The tab the draft belongs to.

    .PARAMETER Text
        The query text.

    .PARAMETER TabConfig
        The tab's connection settings, from ConvertTo-AdHocQueryDraftTabConfig.

    .PARAMETER Path
        The draft store. Defaults to Get-AdHocQueryDraftPath.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TabId,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $TabConfig,

        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-AdHocQueryDraftPath)
    )

    $Private:Kept = @(Get-AdHocQueryDraft -Path $Path | Where-Object { $_.TabId -ne $TabId })

    $Private:Kept += [PSCustomObject]@{
        TabId     = $TabId
        Text      = $Text
        SavedAt   = [DateTime]::UtcNow.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
        TabConfig = $TabConfig
    }

    Write-AdHocQueryDraftStore -Path $Path -Draft $Private:Kept
}
