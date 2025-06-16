Function Invoke-SanitizeJsonKeys {
    [CmdLetBinding()]
    PARAM(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$JsonString
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName), $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        $ParsedJson = $JsonString | ConvertFrom-Json -ErrorAction Stop -AsHashtable

        $SanitizedObject = Invoke-SanitizeObject -Data $ParsedJson

        return $SanitizedObject | ConvertTo-Json -Depth 10
    }
    catch {
        Write-LogOutput -LogType ERROR -Text "Failed to sanitize JSON keys. Error: $($_.Exception.Message)"
        return $null
    }
}
