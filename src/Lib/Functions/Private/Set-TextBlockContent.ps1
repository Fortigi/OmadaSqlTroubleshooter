function Set-TextBlockContent {
    [CmdLetBinding()]
    PARAM(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $TextBlockObject,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        $CurrentTextBlockContent = $TextBlockObject.Text
        $TextBlockObject.Text = $Content
        "{0} set from '{1}' to '{2}'" -f $TextBlockObject.Name, $CurrentTextBlockContent, $TextBlockObject.Text | Write-LogOutput -LogType DEBUG

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }


}
