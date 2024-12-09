Function Invoke-SanitizeJsonKeys {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$JsonString,

        [Parameter(Mandatory = $false)]
        [string]$ReplacementChar = ""
    )

    $ParsedJson = $JsonString | ConvertFrom-Json -ErrorAction Stop -AsHashtable 

    $SanitizedObject = Invoke-SanitizeObject -Data $ParsedJson

    return $SanitizedObject | ConvertTo-Json -Depth 10
}
