function Set-ConfigMultiValue {
    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $InputString,
        $JoinString = " - "
    )
    try {
        $Value = Split-NameDoIdString -InputString $InputString -JoinString $JoinString
        if (($Value | Measure-Object).Count -eq 1) {
            return ($Value.DoId, $Value.DisplayName -Join (Get-ConfigMultiValueSeparator))
        }
        else {
            return $null
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}

