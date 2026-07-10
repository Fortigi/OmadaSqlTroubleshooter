function Sync-MatchingTabConnections {
    <#
    .SYNOPSIS
    Propagates a connect/disconnect from one tab to every other tab that shares its connection
    identity (same tenant, authentication and credentials): connecting one tab auto-connects the
    matching tabs, disconnecting one disconnects them together.

    .DESCRIPTION
    Matching tabs reuse the source tab's OmadaWeb.PS session (same SessionKey = identity Key), so a
    propagated connect does not trigger a second interactive login. Empty tabs are ignored (there is
    nothing to connect). A re-entrancy guard stops the per-tab Set-SqlConnectionState calls from
    re-triggering this. The originally active tab is restored afterwards.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceTabId,
        [Parameter(Mandatory = $true)]
        [bool]$Connect
    )
    if ($Script:SyncingTabConnections) {
        return
    }
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        $Script:SyncingTabConnections = $true

        $Source = $Script:Tabs | Where-Object { $_.Id -eq $SourceTabId } | Select-Object -First 1
        if ($null -eq $Source) {
            return
        }

        # A duplicated tab is made independent: connecting or disconnecting it must never affect the
        # tab it was duplicated from (or any other tab), so it neither propagates nor receives sync.
        if ($Source.IndependentConnection) {
            return
        }

        $SourceIdentity = Get-TabConnectionIdentity -TabSession $Source
        if ($null -eq $SourceIdentity -or $SourceIdentity.IsEmpty) {
            # A blank tab has nothing to share/auto-connect.
            return
        }

        $ReturnTab = Get-ActiveTabSession
        foreach ($Tab in @($Script:Tabs | Where-Object { $_.Id -ne $SourceTabId })) {
            # Never auto-connect/disconnect an independent (duplicated) tab from another tab's change.
            if ($Tab.IndependentConnection) {
                continue
            }
            $Identity = Get-TabConnectionIdentity -TabSession $Tab
            if ($null -eq $Identity -or $Identity.Key -ne $SourceIdentity.Key) {
                continue
            }

            $TabConnected = if ($Tab.Id -eq $Script:ActiveTabId) { [bool]$Script:ConnectionStatus } else { [bool]$Tab.ConnectionStatus }

            if ($Connect -and -not $TabConnected) {
                "Auto-connecting tab '{0}' (matches connected tab)." -f $Tab.DisplayName | Write-LogOutput -LogType DEBUG
                Set-ActiveTabContext -TabSession $Tab
                # Share the source's session so this connect reuses its login instead of prompting.
                $Script:RunTimeData.RestMethodParam.SessionKey = $SourceIdentity.Key
                $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false
                Set-SqlConnectionState -Status $true
            }
            elseif (-not $Connect -and $TabConnected) {
                "Auto-disconnecting tab '{0}' (matches disconnected tab)." -f $Tab.DisplayName | Write-LogOutput -LogType DEBUG
                Set-ActiveTabContext -TabSession $Tab
                Set-SqlConnectionState -Status $false
            }
        }

        if ($null -ne $ReturnTab) {
            Set-ActiveTabContext -TabSession $ReturnTab
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
    finally {
        $Script:SyncingTabConnections = $false
    }
}
