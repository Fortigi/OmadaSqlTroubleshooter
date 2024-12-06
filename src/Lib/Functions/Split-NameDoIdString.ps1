function Split-NameDoIdString {
    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $InputString,
        $JoinString = " - "
    )
    try {
        if ([string]::IsNullOrEmpty($InputString)) {
            "Returning null because inputstring is empty" | Write-LogOutput -LogType VERBOSE
            return $null
        }
        else {

            "Returning object" | Write-LogOutput -LogType VERBOSE
            $LastIndex = $InputString.LastIndexOf($JoinString)
            $DisplayName = $InputString.Substring(0, $LastIndex).Trim()
            $DoId = $InputString.Substring($LastIndex + ($JoinString.Length - 1)).Trim()

            "Returning object, DoId: {0}, DisplayName: {1}" -f $DoId, $DisplayName | Write-LogOutput -LogType VERBOSE
            return [PSCustomObject]@{
                DoId        = $DoId
                DisplayName = $DisplayName

            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
