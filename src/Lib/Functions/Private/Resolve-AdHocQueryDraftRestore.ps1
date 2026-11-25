function Resolve-AdHocQueryDraftRestore {
    <#
    .SYNOPSIS
        Decides, for each kept ad-hoc query draft, whether it goes back into a tab that was restored
        or needs a tab of its own.

    .DESCRIPTION
        After a normal close the tab a draft belongs to is in tabs.clixml and has just been restored,
        so the draft is put back into it. After a crash tabs.clixml still describes the session before
        (it is only written while closing), so a draft can belong to a tab that no longer exists; it
        is opened in a new tab instead of being dropped.

        Pure, so this pairing is tested rather than discovered after a crash.

    .PARAMETER Draft
        The drafts, from Get-AdHocQueryDraft.

    .PARAMETER TabId
        The ids of the tabs that are open now.

    .OUTPUTS
        [PSCustomObject] @{ Attach = @(@{ TabId; Draft }); Open = @(Draft) }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Draft = @(),

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$TabId = @()
    )

    $Private:Open = [System.Collections.Generic.List[object]]::new()
    $Private:Attach = [System.Collections.Generic.List[object]]::new()
    $Private:Known = @($TabId | Where-Object { ![string]::IsNullOrWhiteSpace($_) })

    foreach ($Private:Item in @($Draft | Where-Object { $null -ne $_ })) {
        if ($Private:Known -contains $Private:Item.TabId) {
            $Private:Attach.Add([PSCustomObject]@{ TabId = $Private:Item.TabId; Draft = $Private:Item })
        }
        else {
            $Private:Open.Add($Private:Item)
        }
    }

    return [PSCustomObject]@{
        Attach = $Private:Attach.ToArray()
        Open   = $Private:Open.ToArray()
    }
}
