Function Invoke-SanitizeObject {
    [CmdLetBinding()]
    PARAM(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$Data
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName), $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        $ReplacementChar = "_"
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
    catch {
        Write-LogOutput -LogType ERROR -Text "Failed to sanitize object. Error: $($_.Exception.Message)"
        return $null
    }
}
