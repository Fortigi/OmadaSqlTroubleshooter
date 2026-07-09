function Restore-TabSessions {
    <#
    .SYNOPSIS
    Creates the initial tab(s) on startup: restores previously persisted tabs (config\tabs.clixml)
    if present, else migrates the legacy single-session config into "tab 1" once, else opens a
    single fresh empty tab. Prompts to reconnect ONCE for all restored tabs (not once per tab);
    each tab's reconnect attempt then succeeds or fails independently of the others.
    #>
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        $MaxCapacity = if ($null -ne $Script:AppGlobalConfig -and $Script:AppGlobalConfig.TabCapacity -gt 0) { $Script:AppGlobalConfig.TabCapacity } else { 8 }
        $TabsPath = Join-Path $Script:RunTimeConfig.AppDataFolder -ChildPath "config\tabs.clixml"

        $Persisted = $null
        if (Test-Path $TabsPath -PathType Leaf) {
            try {
                $Persisted = Import-Clixml -Path $TabsPath
            }
            catch {
                "Failed to load persisted tab sessions, starting fresh: {0}" -f $_.Exception.Message | Write-LogOutput -LogType WARNING
            }
        }

        if ($null -ne $Persisted -and ($Persisted.Tabs | Measure-Object).Count -gt 0) {
            $TabsToRestore = @($Persisted.Tabs | Select-Object -First $MaxCapacity)
            if ($TabsToRestore.Count -lt @($Persisted.Tabs).Count) {
                "Persisted tab file contained more tabs than the configured capacity ({0}); truncating." -f $MaxCapacity | Write-LogOutput -LogType WARNING
            }

            $AutoConnect = $false
            $NonEmptyTabs = @($TabsToRestore | Where-Object { ![string]::IsNullOrWhiteSpace($_.BaseUrl) })
            if ($NonEmptyTabs.Count -gt 0) {
                $Choice = Open-ChoiceForm -Title "Reconnect?" -Message ("Reconnect all {0} saved tab(s) using their existing connection settings?" -f $NonEmptyTabs.Count) -LeftButtonReturnValue 2 -RightButtonReturnValue 1
                $AutoConnect = ($Choice -eq 2)
            }

            $RestoredTabs = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($TabConfig in $TabsToRestore) {
                try {
                    $NewTab = New-TabSession -RestoreFrom $TabConfig -AutoConnect:$AutoConnect
                    if ($null -ne $NewTab) {
                        $RestoredTabs.Add($NewTab)
                    }
                }
                catch {
                    "Failed to restore tab '{0}': {1}" -f $TabConfig.DisplayName, $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            }

            if ($RestoredTabs.Count -gt 0) {
                $ActiveTab = $RestoredTabs | Where-Object { $_.Id -eq $Persisted.ActiveTabId } | Select-Object -First 1
                if ($null -eq $ActiveTab) {
                    $ActiveTab = $RestoredTabs[0]
                }
                $Script:MainForm.Elements.TabControlSessions.SelectedItem = $ActiveTab.TabItem
                return
            }
        }

        if ($null -ne $Script:LegacyConfigForMigration) {
            "Migrating legacy single-session config into tab 1." | Write-LogOutput -LogType DEBUG
            $MigratedConfig = ConvertTo-TabSessionConfig -LegacyAppConfig $Script:LegacyConfigForMigration
            $Choice = Open-ChoiceForm -Title "Reconnect?" -Message ("Reconnect to '{0}' using existing connection settings?" -f $MigratedConfig.BaseUrl) -LeftButtonReturnValue 2 -RightButtonReturnValue 1
            $NewTab = New-TabSession -RestoreFrom $MigratedConfig -AutoConnect:($Choice -eq 2)
            if ($null -ne $NewTab) {
                Save-TabSessions
                return
            }
        }

        "No persisted tabs found; opening a fresh tab." | Write-LogOutput -LogType DEBUG
        New-TabSession | Out-Null
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
