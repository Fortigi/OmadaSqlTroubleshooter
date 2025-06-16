function Set-WindowSize {
    [CmdLetBinding()]
    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Form,
        [parameter(Mandatory = $true)]
        [string]$Setting
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName), $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        $Form.Width = [Int]::Abs($Setting.Split("x")[0])
        $Form.Height = [Int]::Abs($Setting.Split("x")[1])

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
