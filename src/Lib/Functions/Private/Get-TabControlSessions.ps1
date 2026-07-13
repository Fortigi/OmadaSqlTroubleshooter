function Get-TabControlSessions {
    <#
    .SYNOPSIS
    Returns the outer window's TabControl. Must be resolved via $Script:MainForm.Definition's own
    namescope (FindName), NOT via $Script:MainForm.Elements - the latter is repointed by
    Set-ActiveTabContext onto whichever tab is active and no longer contains outer-shell-only
    controls like the TabControl itself once any tab has been activated.
    #>
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        return $Script:MainForm.Definition.FindName("TabControlSessions")
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
