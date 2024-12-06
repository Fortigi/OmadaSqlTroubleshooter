function Set-ConfigMultiValue {
    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $InputString,
        $JoinString = " - "
    )
    try {
        if([string]::IsNullOrEmpty($InputString)) {
            "Returning null because inputstring is empty" | Write-LogOutput -LogType VERBOSE
            return $null
        }
        else{
            "Returning config string using join string '{0}'" -f $JoinString | Write-LogOutput -LogType VERBOSE
            return ($InputString -Split $JoinString) -Join (Get-ConfigMultiValueSeparator)
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}

