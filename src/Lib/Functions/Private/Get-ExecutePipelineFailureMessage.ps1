function Get-ExecutePipelineFailureMessage {
    <#
    .SYNOPSIS
    The text Complete-ExecuteQueryPipeline reports for a failed execute pipeline.

    .DESCRIPTION
    A write the tenant refused with 401 right after it served this run's reads is a missing OData
    permission, not an expired session - but OmadaWeb.PS words it as the latter, which sent users off
    to sign in again for a problem only an administrator can fix. Get-OmadaWritePermissionMessage
    recognizes that case; this puts its explanation first and keeps the original error text after it,
    so the log loses nothing. Every other failure keeps the wording it always had.

    Its own function so that choosing the wording does not add a branch to
    Complete-ExecuteQueryPipeline, which is held to its complexity baseline.

    .PARAMETER Outcome
    The failed pipeline outcome: FailedStep, ErrorRecord, CompletedSteps and Steps.

    .OUTPUTS
    [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        $Outcome
    )

    $Private:PermissionMessage = Get-OmadaWritePermissionMessage -Outcome $Outcome
    if ($null -ne $Private:PermissionMessage) {
        return "{0} Details: step '{1}': {2}" -f $Private:PermissionMessage, $Outcome.FailedStep, $Outcome.ErrorRecord.Exception.Message
    }

    return "The query pipeline failed at step '{0}': {1}" -f $Outcome.FailedStep, $Outcome.ErrorRecord.Exception.Message
}
