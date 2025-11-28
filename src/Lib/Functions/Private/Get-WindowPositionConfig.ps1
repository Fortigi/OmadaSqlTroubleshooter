function Get-WindowPositionConfig {
    [CmdLetBinding()]
    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Form
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        $Property = "{0}Position" -f $Form.Name
        if ($null -ne $Script:AppConfig.$Property -and $Script:AppConfig.$Property -match "\b\d+x\d+\b") {
            return $Script:AppConfig.$Property
        }
        else {
            return $null
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
