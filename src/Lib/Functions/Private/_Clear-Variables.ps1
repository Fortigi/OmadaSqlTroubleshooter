function Clear-Variables {
    [CmdLetBinding()]
    param()

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        $EndVariables = Get-Variable
        $SkipVariableNames = @("WshShell", "WhatIfPreference", "WarningPreference", "VerbosePreference", "true", "PSItem", "Task")
        foreach ($EndVariable in $EndVariables) {
            if ($EndVariable.Name -notin $StartVariables.Name -and $EndVariable.Name -notin $SkipVariableNames) {
                try {
                    if (($ExecutionContext.SessionState.PSVariable.Get("Global:$($EndVariable.Name)") | Measure-Object).Count -gt 0) {
                        Write-Verbose "Global:$($EndVariable.Name)"
                        Get-Variable -Scope Global | Where-Object { $_.Name -eq $EndVariable.name } | Remove-Variable -Scope Global -Force -ErrorAction SilentlyContinue
                    }
                    elseif (($ExecutionContext.SessionState.PSVariable.Get("Script:$($EndVariable.Name)") | Measure-Object).Count -gt 0) {
                        Write-Verbose "Script:$($EndVariable.Name)"
                        #Get-Variable -Scope Script | Where-Object { $_.Name -eq $EndVariable.name } | Remove-Variable -Scope Script -Force -ErrorAction SilentlyContinue
                    }
                    elseif (($ExecutionContext.SessionState.PSVariable.Get("Local:$($EndVariable.Name)") | Measure-Object).Count -gt 0) {
                        Write-Verbose "Local:$($EndVariable.Name)"
                        Get-Variable -Scope Local | Where-Object { $_.Name -eq $EndVariable.name } | Remove-Variable -Scope Local -Force -ErrorAction SilentlyContinue
                    }
                    elseif (($ExecutionContext.SessionState.PSVariable.Get("Private:$($EndVariable.Name)") | Measure-Object).Count -gt 0) {
                        Write-Verbose "Private:$($EndVariable.Name)"
                        Get-Variable -Scope Local | Where-Object { $_.Name -eq $EndVariable.name } | Remove-Variable -Scope Local -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        Write-Verbose "__:$($EndVariable.Name)"
                        Get-Variable | Where-Object { $_.Name -eq $EndVariable.name } | Remove-Variable -Force -ErrorAction SilentlyContinue
                    }
                }
                catch {
                }
            }
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }

}
