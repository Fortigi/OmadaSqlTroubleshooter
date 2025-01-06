Function Invoke-SanitizeObject {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$Data
    )

    if ($Data -is [hashtable]) {
        $NewData = @{}
        foreach ($Key in $Data.Keys) {
            $NewKey = $Key -replace '[^A-Za-z0-9_\-]', $ReplacementChar
            if ($Data[$Key] -is [hashtable]) {
                $NewData[$NewKey] = Invoke-SanitizeObject -Data $Data[$Key]
            }
            elseif ($Data[$Key] -is [array]) {
                $NewData[$NewKey] = $Data[$Key] | ForEach-Object { Invoke-SanitizeObject -Data $_ }
            }
            else {
                $NewData[$NewKey] = $Data[$Key]
            }
        }
        return $NewData
    }
    elseif ($Data -is [array]) {
        return $Data | ForEach-Object { Invoke-SanitizeObject -Data $_ }
    }
    else {
        return $Data
    }
}
