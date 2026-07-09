function Update-TabHeaderTitle {
    <#
    .SYNOPSIS
    Refreshes a tab's header text to "<DisplayName>" or "<DisplayName>*" when the tab has
    unsaved query changes.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        $Title = if ($TabSession.IsDirty) { "{0}*" -f $TabSession.DisplayName } else { $TabSession.DisplayName }
        $TabSession.TabItem.Header.Children[0].Text = $Title
        $TabSession.TabItem.ToolTip = $TabSession.DisplayName
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
