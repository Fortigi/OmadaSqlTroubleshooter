function Resolve-ExecuteQueryScope {
    <#
    .SYNOPSIS
        Whether an execute runs the saved query or an ad-hoc one, as the two pipeline context values
        that differ between them.

    .DESCRIPTION
        A saved query is fetched, saved when it changed, and executed - through the temporary
        TMP_<InstanceGuid> object only for a selection or a multi-statement or cross-database run.

        An ad-hoc query has no object to fetch or save, so:

          SkipSave       $true. The pipeline's save step would GET C_P_SQLTROUBLESHOOTING() with no
                         id; skipping it is the supported way to leave the user's queries untouched.
          SelectionText  the whole editor text when nothing is selected. The pipeline creates the
                         temporary object whenever there is a selection, so an ad-hoc query runs
                         exactly like executing a selection of everything - the path already proven
                         for issue #151 and #152 - and the temporary object is deleted afterwards.
                         Nothing the user owns is created or changed on the tenant.

        A saved query keeps the selection as it was (possibly none) and is saved as before.

        Pure: the context is assembled on the UI thread from these values and Invoke-OmadaExecutePipeline
        needs no knowledge of ad-hoc queries at all, so the background worker's function list is
        unchanged.

    .PARAMETER QueryDoId
        The selected query's DoId, or $null.

    .PARAMETER QueryText
        The full editor text.

    .PARAMETER SelectionText
        The selected text, or $null when nothing is selected.

    .OUTPUTS
        [PSCustomObject] @{ IsAdHoc; SkipSave; SelectionText }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $QueryDoId,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$QueryText,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SelectionText
    )

    $Private:IsAdHoc = Test-AdHocQuery -QueryDoId $QueryDoId
    $Private:Selection = if ([string]::IsNullOrWhiteSpace($SelectionText)) { $null } else { $SelectionText }

    if ($Private:IsAdHoc -and $null -eq $Private:Selection) {
        $Private:Selection = $QueryText
    }

    return [PSCustomObject]@{
        IsAdHoc       = $Private:IsAdHoc
        SkipSave      = $Private:IsAdHoc
        SelectionText = $Private:Selection
    }
}
