function Set-ButtonText {
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $ButtonTextObject,
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        $CurrentButtonTextContent = $ButtonTextObject.Text
        if ($CurrentButtonTextContent -ne $Value) {
            $ButtonTextObject.Text = $Value
            "{0} set from '{1}' to '{2}'" -f $ButtonTextObject.Name, $CurrentButtonTextContent, $ButtonTextObject.Text | Write-LogOutput -LogType DEBUG
        }
        else{
            "{0} text '{1}' unchanged" -f $ButtonTextObject.Name, $ButtonTextObject.Text | Write-LogOutput -LogType DEBUG
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }


}
