function Resolve-OmadaRequestFailure {
    <#
    .SYNOPSIS
    Classify a failed Omada request and drive the app's response to it. UI thread only.

    .DESCRIPTION
    Extracted verbatim from Invoke-OmadaPSWebRequestWrapper's catch block so that a request issued on
    a background worker is classified by exactly the same rules as one issued inline (issue #40).
    Everything it does - Set-SqlConnectionState, reading $Script:AppConfig.BaseUrl, writing
    $Script:RunTimeData.SkipRetryRequest - is UI-runspace state, which is why the worker returns the
    ErrorRecord rather than trying to interpret it.

    .NOTES
    Two of the three branches end in Write-Error -ErrorAction Stop, which THROWS. That is not an
    oversight being preserved for its own sake: it is how the tenant-level failures (the OData
    endpoint not enabled, and Unauthorized) reach the caller as errors rather than as return values,
    and the wrapper's tests assert it. The third branch returns the ErrorRecord, which is the
    documented contract callers test with -is [ErrorRecord].

    Because of that, a caller invoking this from a background completion block must be prepared for
    it to throw - the poll timer's own try/catch logs it - whereas the synchronous wrapper lets it
    propagate to whoever called the wrapper.

    .PARAMETER ErrorRecord
    The failure, either caught inline or returned from Invoke-OmadaRequestCore.

    .OUTPUTS
    The ErrorRecord, for the unclassified case. The two classified cases throw.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ErrorRecord
    )

    if (![string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails?.Message) -and $ErrorRecord.ErrorDetails.Message -like "*Resource not found for the segment 'C_P_SQLTROUBLESHOOTING'*") {
        $Message = "OData Endpoint for SQL Troubleshooting not enabled at tenant {0}.`n`r`n`rError returned by Omada:`n`r`n`r{1}" -f [system.uri]::New($Script:AppConfig.BaseUrl).Host, $ErrorRecord.ErrorDetails.Message
        # Route the teardown through the state function, exactly as the Unauthorized branch below
        # already does. This used to hand-write four status-bar fields while leaving
        # $Script:ConnectionStatus untouched, so the button, the dropdowns and the Display name went
        # on claiming the tab was connected.
        Set-SqlConnectionState -Status $false
        $Message | Write-Error -ErrorAction Stop -TargetObject $ErrorRecord
        $Script:RunTimeData.SkipRetryRequest = $true
    }
    elseif ($null -ne $ErrorRecord.Exception?.Response?.StatusCode -and $ErrorRecord.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::Unauthorized) {
        $Message = "Access denied to {0}, message:`n`r{1}" -f [system.uri]::New($Script:AppConfig.BaseUrl).Host, $ErrorRecord.ErrorDetails.Message
        Set-SqlConnectionState -Status $false
        $Message | Write-Error -ErrorAction Stop -TargetObject $ErrorRecord
        $Script:RunTimeData.SkipRetryRequest = $true
    }
    else {
        $ErrorRecord
    }
}
