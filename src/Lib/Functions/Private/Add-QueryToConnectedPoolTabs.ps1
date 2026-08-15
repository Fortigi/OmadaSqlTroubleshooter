function Add-QueryToConnectedPoolTabs {
    <#
    .SYNOPSIS
    Adds a newly saved query to the query list of every *connected* tab that shares the active
    tab's connection pool, so the new query is immediately visible in those tabs without each of
    them having to refresh from the server.

    .DESCRIPTION
    A connection pool is identified by Get-TabConnectionIdentity (tenant URL + authentication
    method + credentials). After a "save as new" the query only lands in the tab that saved it; the
    other tabs would not see it until their own Update-QueryList runs (dropdown open / refresh /
    TTL expiry). This function pushes the single new entry into every connected pool member's
    per-tab query cache (QueryListCache.QueryList) and its query dropdown. It is idempotent - an
    entry already present (matched by DoId in the cache, or by FullName in the dropdown) is left
    untouched - so the saving tab, which already has the item, is not duplicated.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DoId,
        [string]$DisplayName,
        [string]$FullName
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        if ([string]::IsNullOrWhiteSpace($DoId)) {
            return
        }

        $ActiveTab = Get-ActiveTabSession
        if ($null -eq $ActiveTab) {
            return
        }

        $ActiveIdentity = Get-TabConnectionIdentity -TabSession $ActiveTab
        if ($null -eq $ActiveIdentity -or $ActiveIdentity.IsEmpty -or [string]::IsNullOrWhiteSpace($ActiveIdentity.Key)) {
            return
        }

        foreach ($Tab in $Script:Tabs) {
            $Connected = if ($Tab.Id -eq $Script:ActiveTabId) { [bool]$Script:ConnectionStatus } else { [bool]$Tab.ConnectionStatus }
            if (-not $Connected) {
                continue
            }

            $Identity = Get-TabConnectionIdentity -TabSession $Tab
            if ($null -eq $Identity -or $Identity.Key -ne $ActiveIdentity.Key) {
                continue
            }

            # Keep the per-tab query cache in sync (used for TTL/name lookups), matching on DoId.
            if ($null -eq $Tab.RunTimeData.QueryListCache.QueryList) {
                $Tab.RunTimeData.QueryListCache.QueryList = @()
            }
            # Compare keys as strings: Update-QueryList stores the DoId key with its native type
            # (often [int]), while $DoId here is a string, so a raw -contains would miss numeric keys
            # and keep re-adding the same query - breaking idempotence.
            $DoIdString = [string]$DoId
            $AlreadyCached = @($Tab.RunTimeData.QueryListCache.QueryList | Where-Object { $_ -is [System.Collections.IDictionary] -and (@($_.Keys | ForEach-Object { [string]$_ }) -contains $DoIdString) }).Count -gt 0
            if (-not $AlreadyCached) {
                $Tab.RunTimeData.QueryListCache.QueryList += @{ $DoId = $DisplayName }
            }

            # Add the item to the tab's query dropdown, matching on the displayed "DisplayName - DoId".
            $ComboBox = $Tab.Elements.ComboBoxSelectQuery
            if ($null -ne $ComboBox) {
                $AlreadyListed = @($ComboBox.Items | Where-Object { $_.Content -eq $FullName }).Count -gt 0
                if (-not $AlreadyListed) {
                    $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                    $ComboBoxSelectQueryItem.Content = $FullName
                    $ComboBox.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                    "Added new query '{0}' to connected pool tab '{1}'." -f $FullName, $Tab.DisplayName | Write-LogOutput -LogType DEBUG
                }
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
