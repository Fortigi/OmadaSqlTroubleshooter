function Set-TextBoxWrapping {
    [CmdLetBinding()]
    PARAM(
        $TextBox,
        [bool]$Wrap = $false
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        "Set TextBox wrapping to {0}" -f $Wrap | Write-LogOutput -LogType DEBUG
        if ($Wrap) {
            $TextBox.TextWrapping = "WrapWithOverflow"
        }
        else {
            $TextBox.TextWrapping = "NoWrap"
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
