function New-TabSession {
    <#
    .SYNOPSIS
    Creates a new tab: an independent session with its own connection fields, query editor,
    results grid, status bar, and OmadaWeb.PS SessionKey. Enforces the configured tab capacity.

    .PARAMETER RestoreFrom
    A tab-config object (see ConvertTo-TabSessionConfig) to restore instead of starting blank -
    used when re-opening previously persisted tabs, or migrating a legacy single-session config.

    .PARAMETER AutoConnect
    When set, attempts to reconnect using the restored/pre-filled connection settings.
    #>
    [CmdLetBinding()]
    param(
        [PSCustomObject]$RestoreFrom,
        [switch]$AutoConnect
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        $MaxCapacity = if ($null -ne $Script:AppGlobalConfig -and $Script:AppGlobalConfig.TabCapacity -gt 0) { $Script:AppGlobalConfig.TabCapacity } else { 8 }
        if (-not (Test-TabCapacity -CurrentCount $Script:Tabs.Count -MaxCapacity $MaxCapacity)) {
            "Cannot open a new tab: capacity of {0} tabs reached." -f $MaxCapacity | Write-LogOutput -LogType WARNING
            return $null
        }

        $TabId = if ($null -ne $RestoreFrom -and ![string]::IsNullOrWhiteSpace($RestoreFrom.Id)) { $RestoreFrom.Id } else { (New-Guid).Guid }
        $DisplayName = if ($null -ne $RestoreFrom -and ![string]::IsNullOrWhiteSpace($RestoreFrom.DisplayName)) { $RestoreFrom.DisplayName } else { Get-DefaultTabDisplayName }

        $XamlPath = Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\MainFormTabContent.xaml"
        $Xaml = Get-Content -Path $XamlPath -Raw
        $Form = Initialize-FormObject -Xaml $Xaml

        $DefaultTabConfig = [PSCustomObject]@{
            BaseUrl               = $null
            CurrentSqlQuery       = [PSCustomObject]@{ DoId = $null; DisplayName = $null; FullName = $null }
            LastAuthentication    = "Browser"
            UserName              = $null
            Password              = $null
            EntraApplicationIdUri = $null
            EntraIdTenantId       = $null
            MyCreatedQueriesOnly  = $false
            MyUpdatedQueriesOnly  = $false
            SavePassword          = $false
            IdentityUserName      = $null
            CurrentDataConnection = [PSCustomObject]@{ DoId = $null; DisplayName = $null; FullName = $null }
        }

        $NewTab = [PSCustomObject]@{
            Id               = $TabId
            DisplayName      = $DisplayName
            IsDirty          = $false
            Form             = $Form
            Elements         = $Form.Elements
            TabItem          = $null
            ConnectionStatus = $false
            PendingTask      = $null
            AppConfig        = $(if ($null -ne $RestoreFrom) { $RestoreFrom } else { $DefaultTabConfig })
            RunTimeData      = [PSCustomObject]@{
                RestMethodParam                = @{
                    Uri                   = $null
                    Method                = "GET"
                    AuthenticationType    = $null
                    UseWebView2           = $null
                    EntraApplicationIdUri = $null
                    EntraIdTenantId       = $null
                    ForceAuthentication   = $false
                    InPrivate             = $false
                    SessionKey            = $TabId
                }
                AuthenticationRetryCount       = 0
                QuerySaved                     = $false
                Password                       = $null
                QueryText                      = $null
                SqlQueryObject                 = $null
                QueryResult                    = $null
                HistoryResult                  = $null
                CurrentQueryText               = $null
                CurrentSqlQuery                = [PSCustomObject]@{
                    DoId        = $null
                    DisplayName = $null
                    FullName    = $null
                }
                StopWatch                      = $null
                QueryListCache                 = @{
                    QueryList   = $null
                    LastRefresh = Get-Date
                    TTL         = 300
                }
                DataobjdlgAspxAttributeMapping = [PSCustomObject]@{
                    SqlQueryDoId      = "c-13"
                    SqlQueryCreatedBy = "c-2"
                    SqlQueryChangedBy = "c-4"
                }
                SkipRetryRequest                = $false
                SelectionText                   = $null
            }
            WebView          = @{
                Object                  = $null
                Environment             = $null
                EdgeWebview2RuntimePath = $null
                UserDataFolder          = $null
            }
        }

        $TabItem = New-Object System.Windows.Controls.TabItem
        $TabItem.Header = New-TabHeaderControl -TabSession $NewTab
        $TabItem.Content = $Form.Definition
        $NewTab.TabItem = $TabItem
        Update-TabHeaderTitle -TabSession $NewTab

        $AddNewTabItem = $Script:MainForm.Elements.TabControlSessions.Items | Where-Object { $_.Name -eq "TabItemAddNew" }
        $InsertIndex = $Script:MainForm.Elements.TabControlSessions.Items.IndexOf($AddNewTabItem)
        if ($InsertIndex -lt 0) {
            [void]$Script:MainForm.Elements.TabControlSessions.Items.Add($TabItem)
        }
        else {
            $Script:MainForm.Elements.TabControlSessions.Items.Insert($InsertIndex, $TabItem)
        }

        $Script:Tabs.Add($NewTab)

        # Selecting the new TabItem fires TabControlSessions' SelectionChanged synchronously,
        # which calls Set-ActiveTabContext -TabSession $NewTab - from this point on,
        # $Script:MainForm.Elements/$Script:AppConfig/$Script:RunTimeData/etc. all refer to $NewTab.
        $Script:MainForm.Elements.TabControlSessions.SelectedItem = $TabItem

        Import-EventObjects -ClassName "MainFormTabContent"

        "Pre-set tab components from config" | Write-LogOutput -LogType DEBUG
        $Script:MainForm.Elements.TextBoxURL.Text = $Script:AppConfig.BaseUrl
        $Script:MainForm.Elements.TextBoxURL.IsEnabled = $true

        if ($Script:AppConfig.MyCreatedQueriesOnly) {
            $Script:MainForm.Elements.CheckboxMyCreatedQueries.IsChecked = $true
        }
        if ($Script:AppConfig.MyUpdatedQueriesOnly) {
            $Script:MainForm.Elements.CheckboxMyUpdatedQueries.IsChecked = $true
        }

        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.LastAuthentication)) {
            $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedValue = $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.Items | Where-Object { $_.Content -eq $Script:AppConfig.LastAuthentication }
        }

        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.UserName)) {
            $Script:MainForm.Elements.TextBoxUserName.Text = $Script:AppConfig.UserName
        }

        if ($null -ne $Script:AppConfig.Password) {
            $Script:MainForm.Elements.TextBoxPassword.Password = $Script:AppConfig.Password | Get-SecureStringFromText
        }

        if ($Script:AppConfig.SavePassword) {
            $Script:MainForm.Elements.CheckboxSavePassword.IsChecked = $true
        }

        if ($null -ne $Script:AppConfig.UserName -and $null -ne $Script:AppConfig.Password) {
            $Script:RunTimeData.RestMethodParam.Credential = [System.Management.Automation.PSCredential]::new($Script:AppConfig.UserName, ($Script:AppConfig.Password | ConvertTo-SecureString))
        }

        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.EntraApplicationIdUri)) {
            $Script:MainForm.Elements.TextBoxAppIdUri.Text = $Script:AppConfig.EntraApplicationIdUri
            $Script:RunTimeData.RestMethodParam.EntraApplicationIdUri = $Script:AppConfig.EntraApplicationIdUri
        }

        if (![string]::IsNullOrWhiteSpace($Script:AppConfig.EntraIdTenantId)) {
            $Script:MainForm.Elements.TextBoxEntraIdTenantId.Text = $Script:AppConfig.EntraIdTenantId
            $Script:RunTimeData.RestMethodParam.EntraIdTenantId = $Script:AppConfig.EntraIdTenantId
        }

        $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false
        Set-AuthenticationOption
        Set-OmadaUrl

        if ($AutoConnect -and (Test-OmadaConnection)) {
            if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentSqlQuery.DoId)) {
                $ComboBoxSelectQueryItem = $Script:MainForm.Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -like "*$($Script:AppConfig.CurrentSqlQuery.DoId)" }
                if ($null -eq $ComboBoxSelectQueryItem) {
                    $ComboBoxSelectQueryItem = New-Object System.Windows.Controls.ComboBoxItem
                    $ComboBoxSelectQueryItem.Content = $Script:AppConfig.CurrentSqlQuery.FullName
                    $Script:MainForm.Elements.ComboBoxSelectQuery.Items.Add($ComboBoxSelectQueryItem) | Out-Null
                    $Script:RunTimeData.CurrentSqlQuery.DisplayName = $Script:AppConfig.CurrentSqlQuery.DisplayName
                    $Script:MainForm.Elements.TextBoxDisplayName.Text = $Script:RunTimeData.CurrentSqlQuery.DisplayName
                }
                $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedValue = $ComboBoxSelectQueryItem
            }

            if (![string]::IsNullOrWhiteSpace($Script:AppConfig.CurrentDataConnection.FullName)) {
                Set-DataConnection
            }
            Test-ConnectionSettings
            Test-ConnectionButton
        }
        else {
            Set-SqlConnectionState -Status $false
        }

        Initialize-WebViewForTab -TabSession $NewTab

        return $NewTab
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
