function Get-ConfigMultiValue {
    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $ConfigObject,
        $JoinString = " - ",
        [switch]$Array
    )
    try {
        if ($Array) {
            "Return split string as array" | Write-LogOutput -LogType VERBOSE

            return $ConfigObject -Split (Get-ConfigMultiValueSeparator)
        }
        else {
            "Returning string using join string '{0}'" -f $JoinString | Write-LogOutput -LogType VERBOSE
            return ($ConfigObject -Split (Get-ConfigMultiValueSeparator)) -Join $JoinString
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}

