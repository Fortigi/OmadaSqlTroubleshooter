function Get-FormPositionConfig {
    [CmdLetBinding()]
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Form
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        $Property = "{0}Position" -f $Form.Name
        if ($null -ne $Script:AppGlobalConfig.$Property -and $Script:AppGlobalConfig.$Property -match "\b\d+x\d+\b") {
            return $Script:AppGlobalConfig.$Property
        }
        else {
            return $null
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
