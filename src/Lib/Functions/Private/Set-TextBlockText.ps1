function Set-TextBlockText {
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $TextBlockObject,
        [Parameter(Mandatory = $false)]
        [string]$Text
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        $CurrentButtonContent = $TextBlockObject.Text
        if ([string]::IsNullOrEmpty($Text)) {
            $TextBlockObject.Text = $null
        }
        else {
            $TextBlockObject.Text = $Text
        }
        $TextBlockObject.Text = $Text
        "{0} set from '{1}' to '{2}'" -f $TextBlockObject.Name, $CurrentButtonContent, $TextBlockObject.Text | Write-LogOutput -LogType DEBUG

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
