function Rename-SqlQuery {
    <#
    .SYNOPSIS
        Renames the active tab's saved query on the tenant.

    .DESCRIPTION
        Asks for the new name (Read-QueryNameInput), checks it locally and then on the tenant, and
        sends a PUT carrying the NAME only (New-OmadaQueryRequest -Kind RenameQuery). The editor's
        text and the data connection are deliberately not part of a rename: unsaved edits stay unsaved,
        exactly as they were.

        Needs the Update right on the OData auth element, like saving; a refusal is reported with the
        tenant's message.

        Without -DoId it renames the active tab's selected query (the toolbar's Rename); the query
        manager passes the query it has selected.

    .PARAMETER DoId
        The query to rename. Omitted: the active tab's selected query.

    .PARAMETER DisplayName
        That query's current name.

    .OUTPUTS
        [string] The new name, or $null when nothing was renamed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$DoId,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3})" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber)))

        $Private:Query = if ([string]::IsNullOrWhiteSpace($DoId)) { Get-SelectedSavedQuery -Action "rename" } else { [PSCustomObject]@{ DoId = $DoId; DisplayName = $DisplayName } }
        if ($null -eq $Private:Query) {
            return $null
        }

        $Private:Name = Read-QueryNameInput -Title "Rename query" -Message ("New name for '{0}':" -f $Private:Query.DisplayName) -DefaultName $Private:Query.DisplayName -CurrentName $Private:Query.DisplayName -ExistingNames @(Get-CachedQueryName -QueryList $Script:RunTimeData.QueryListCache.QueryList) -OkText "Rename"
        if ($null -eq $Private:Name -or $Private:Name.IsUnchanged) {
            return $null
        }

        $Private:Taken = Test-SqlQueryNameTaken -Name $Private:Name.Name -ExcludeDoId $Private:Query.DoId
        if ($false -ne $Private:Taken) {
            Write-SqlQueryNameUnavailable -Name $Private:Name.Name -Taken $Private:Taken
            return $null
        }

        "Rename query {0} to '{1}'" -f $Private:Query.DoId, $Private:Name.Name | Write-LogOutput
        $Private:Response = Invoke-SavedQueryRequest -Request (New-OmadaQueryRequest -Kind "RenameQuery" -Context @{
                BaseUrl   = $Script:AppConfig.BaseUrl
                QueryDoId = $Private:Query.DoId
                QueryName = $Private:Name.Name
            })

        if (-not $Private:Response.Succeeded) {
            "Renaming query '{0}' failed: {1}" -f $Private:Query.DisplayName, $Private:Response.Message | Write-ContainedErrorLog
            return $null
        }

        $Private:NewName = Get-SavedQueryDisplayName -Result $Private:Response.Result -FallbackName $Private:Name.Name
        Complete-SqlQueryRename -DoId $Private:Query.DoId -DisplayName $Private:NewName
        "Query renamed to '{0}'." -f $Private:NewName | Write-LogOutput
        return $Private:NewName
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        return $null
    }
}

function Complete-SqlQueryRename {
    <#
    .SYNOPSIS
        Applies a successful rename to every tab holding the query and every query list of the pool.

    .DESCRIPTION
        Each tab that has the query selected - not only the active one; the query manager can rename a
        query open in a background tab - keeps the new name in its config and run-time state, so a
        later save or execute does not send the old name back, and its header follows.

    .PARAMETER DoId
        The renamed query.

    .PARAMETER DisplayName
        Its new name.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DoId,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    Clear-RecentSqlQueryObject -DoId $DoId

    $Private:FullName = "{0} - {1}" -f $DisplayName, $DoId
    foreach ($Private:Tab in @($Script:Tabs | Where-Object { $null -ne $_ -and [string]$_.AppConfig.CurrentSqlQuery.DoId -eq $DoId })) {
        $Private:Tab.AppConfig.CurrentSqlQuery = [PSCustomObject]@{ DoId = $Private:Tab.AppConfig.CurrentSqlQuery.DoId; DisplayName = $DisplayName; FullName = $Private:FullName }
        $Private:Tab.RunTimeData.CurrentSqlQuery.DisplayName = $DisplayName
        $Private:Tab.RunTimeData.CurrentSqlQuery.FullName = $Private:FullName
        if ($Private:Tab.Id -eq $Script:ActiveTabId) {
            $Script:AppConfig = $Private:Tab.AppConfig
        }
    }

    Update-QueryInConnectedPoolTabs -DoId $DoId -DisplayName $DisplayName

    foreach ($Private:Tab in @($Script:Tabs | Where-Object { $null -ne $_ -and [string]$_.AppConfig.CurrentSqlQuery.DoId -eq $DoId })) {
        Update-TabHeaderTitle -TabSession $Private:Tab
    }
}

function Get-SavedQueryDisplayName {
    <#
    .SYNOPSIS
        The name a write answered with, or the one that was sent when the answer carries none.

    .DESCRIPTION
        OData may answer a PUT with the updated object or with 204 No Content. The object's
        DisplayName is the tenant's own rendering of the name and wins when it is there.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        $Result,

        [string]$FallbackName
    )

    if ($null -ne $Result -and ![string]::IsNullOrWhiteSpace($Result.DisplayName)) {
        return [string]$Result.DisplayName
    }

    return $FallbackName
}

function Write-SqlQueryNameUnavailable {
    <#
    .SYNOPSIS
        Tells the user why a name cannot be used: taken on the tenant, or the tenant could not be asked.

    .PARAMETER Name
        The name.

    .PARAMETER Taken
        Test-SqlQueryNameTaken's answer: $true, or $null when it could not ask.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [string]$Name,

        [AllowNull()]
        $Taken
    )

    if ($true -eq $Taken) {
        "A query named '{0}' already exists in Omada. Choose another name." -f $Name | Write-LogOutput -LogType WARNING
        return
    }

    "Could not check with Omada whether the name '{0}' is free; nothing was changed. Try again." -f $Name | Write-LogOutput -LogType WARNING
}
