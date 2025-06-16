function Set-LabelContent {
    [CmdLetBinding()]
    PARAM(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $LabelObject,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName), $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        $CurrentButtonContent = $LabelObject.Content
        $LabelObject.Content = $Content
        "{0} set from '{1}' to '{2}'" -f $LabelObject.Name, $CurrentButtonContent, $LabelObject.Content | Write-LogOutput -LogType DEBUG

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }


}
