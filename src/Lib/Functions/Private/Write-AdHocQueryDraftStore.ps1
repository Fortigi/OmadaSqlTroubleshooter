function Write-AdHocQueryDraftStore {
    <#
    .SYNOPSIS
        Replaces the ad-hoc query draft store with the given drafts.

    .DESCRIPTION
        The one place the store is written, so it is written the same way every time:

          - No drafts means no file. An empty store left behind would be read on every start for
            nothing, and its absence is the cheapest possible "nothing to restore".
          - Written to a temporary file next to it and then moved over it. The store exists for the
            case where the process dies, so it must never be left half-written by the process dying
            while writing it: a move within one volume replaces the file in a single step.

    .PARAMETER Path
        The draft store.

    .PARAMETER Draft
        Every draft the store should hold afterwards.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Draft = @()
    )

    $Private:Entries = @($Draft | Where-Object { $null -ne $_ })

    if ($Private:Entries.Count -eq 0) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            Remove-Item -LiteralPath $Path -Force
        }
        return
    }

    $Private:Folder = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $Private:Folder -PathType Container)) {
        New-Item -Path $Private:Folder -ItemType Directory -Force | Out-Null
    }

    $Private:TemporaryPath = "{0}.tmp" -f $Path
    [PSCustomObject]@{
        Version = 1
        Drafts  = $Private:Entries
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Private:TemporaryPath -Encoding utf8 -Force

    Move-Item -LiteralPath $Private:TemporaryPath -Destination $Path -Force
}
