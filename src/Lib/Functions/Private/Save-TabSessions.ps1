function Save-TabSessions {
    <#
    .SYNOPSIS
    Persists every open tab's connection/query state to an encrypted Clixml file (Export-Clixml
    natively round-trips [SecureString] via DPAPI, so the file is not human-readable plaintext -
    matching how the existing single Password field, and OmadaWeb.PS's own cookie cache, are
    already protected). Called once, from MainForm.Definition's Add_Closing.
    #>
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        $TabsPath = Join-Path $Script:RunTimeConfig.AppDataFolder -ChildPath "config\tabs.clixml"
        New-Item -Path (Split-Path $TabsPath) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

        $Snapshot = foreach ($Tab in $Script:Tabs) {
            $SavePassword = [bool]$Tab.Elements.CheckboxSavePassword.IsChecked
            $Password = $null
            if ($SavePassword -and ![string]::IsNullOrWhiteSpace($Tab.Elements.TextBoxPassword.Password)) {
                $Password = $Tab.Elements.TextBoxPassword.Password | ConvertTo-SecureString -Force -AsPlainText | ConvertFrom-SecureString
            }

            [PSCustomObject]@{
                Id                    = $Tab.Id
                DisplayName           = $Tab.DisplayName
                BaseUrl               = $Tab.AppConfig.BaseUrl
                CurrentSqlQuery       = $Tab.AppConfig.CurrentSqlQuery
                LastAuthentication    = $Tab.AppConfig.LastAuthentication
                UserName              = $Tab.AppConfig.UserName
                Password              = $Password
                EntraApplicationIdUri = $Tab.AppConfig.EntraApplicationIdUri
                EntraIdTenantId       = $Tab.AppConfig.EntraIdTenantId
                MyCreatedQueriesOnly  = $Tab.AppConfig.MyCreatedQueriesOnly
                MyUpdatedQueriesOnly  = $Tab.AppConfig.MyUpdatedQueriesOnly
                SavePassword          = $SavePassword
                IdentityUserName      = $Tab.AppConfig.IdentityUserName
                CurrentDataConnection = $Tab.AppConfig.CurrentDataConnection
            }
        }
        $Snapshot = @($Snapshot)

        [PSCustomObject]@{
            Tabs        = $Snapshot
            ActiveTabId = $Script:ActiveTabId
        } | Export-Clixml -Path $TabsPath -Force

        "Saved {0} tab session(s) to {1}" -f $Snapshot.Count, $TabsPath | Write-LogOutput -LogType DEBUG
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
