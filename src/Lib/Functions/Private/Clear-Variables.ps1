function Clear-Variables {
    try {

        $EndVariables = Get-Variable
        $SkipVariableNames = @("WshShell", "WhatIfPreference", "WarningPreference", "VerbosePreference", "true", "PSItem", "Task")
        foreach ($EndVariable in $EndVariables) {
            if ($EndVariable.Name -notin $StartVariables.Name -and $EndVariable.Name -notin $SkipVariableNames) {
                try {
                    Remove-Variable -Name $EndVariable.Name -Force -ErrorAction SilentlyContinue
                }
                catch {}
            }
        }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }

}
