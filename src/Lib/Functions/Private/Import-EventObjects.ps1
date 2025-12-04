function Import-EventObjects {
    [CmdletBinding()]
    param (
        [string]$ClassName
    )

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

    Get-ChildItem -Path (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "Lib\Events") -Filter *.ps1 | Where-Object { $_.Name -like "$($ClassName).*" -and $_.Name -notlike "_*.ps1" } | ForEach-Object {

        "Loading event {0}" -f $_.Name | Write-LogOutput -LogType DEBUG
        try {

            . $_.FullName
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    }
}
