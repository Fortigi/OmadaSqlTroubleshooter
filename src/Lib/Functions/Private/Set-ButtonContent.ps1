function Set-ButtonContent {
    [CmdLetBinding()]
    PARAM(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $ButtonObject,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName), $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        $CurrentButtonContent = $ButtonObject.Content
        $ButtonObject.Content = $Content
        "{0} set from '{1}' to '{2}'" -f $ButtonObject.Name, $CurrentButtonContent, $ButtonObject.Content | Write-LogOutput -LogType DEBUG

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }


}
