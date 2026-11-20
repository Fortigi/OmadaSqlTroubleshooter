function Invoke-SavedQueryRequest {
    <#
    .SYNOPSIS
        Sends one request built by New-OmadaQueryRequest on the UI thread, and says whether it worked.

    .DESCRIPTION
        Invoke-OmadaPSWebRequestWrapper reports a failure in three ways: it throws for the two failures
        Resolve-OmadaRequestFailure classifies, it returns the ErrorRecord for any other, and a
        successful DELETE (or a PUT answered 204 No Content) returns $null, which is NOT a failure. This
        folds all of that into one answer, so rename and delete cannot each get a different one of
        those cases wrong.

        The failure's message is returned, not logged, so the caller can say which action failed.

    .PARAMETER Request
        @{ Method; Uri; Body }, from New-OmadaQueryRequest.

    .OUTPUTS
        [PSCustomObject] @{ Succeeded; Result; Message }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Request
    )

    $Script:RunTimeData.RestMethodParam.Uri = $Request.Uri
    $Script:RunTimeData.RestMethodParam.Method = $Request.Method
    $Script:RunTimeData.RestMethodParam.Body = $Request.Body
    "QueryUrl: {0}" -f $Request.Uri | Write-LogOutput -LogType DEBUG

    try {
        $Private:Result = Invoke-OmadaPSWebRequestWrapper
    }
    catch {
        return [PSCustomObject]@{ Succeeded = $false; Result = $null; Message = $_.Exception.Message }
    }

    if ($Private:Result -is [System.Management.Automation.ErrorRecord]) {
        return [PSCustomObject]@{ Succeeded = $false; Result = $null; Message = $Private:Result.Exception.Message }
    }

    return [PSCustomObject]@{ Succeeded = $true; Result = $Private:Result; Message = $null }
}
