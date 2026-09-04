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
        [switch]$AutoConnect,
        # Create the tab cheaply (header + fields only) and defer the reconnect + WebView2/Monaco
        # init until the tab is first viewed (Complete-TabMaterialization). Used by Restore-TabSessions
        # for lazy startup; interactively-created tabs are never deferred.
        [switch]$Deferred
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        $MaxCapacity = if ($null -ne $Script:AppGlobalConfig -and $Script:AppGlobalConfig.TabCapacity -gt 0) { $Script:AppGlobalConfig.TabCapacity } else { 8 }
        if (-not (Test-TabCapacity -CurrentCount $Script:Tabs.Count -MaxCapacity $MaxCapacity)) {
            "Cannot open a new tab: capacity of {0} tabs reached." -f $MaxCapacity | Write-LogOutput -LogType WARNING
            return $null
        }

        $TabId = if ($null -ne $RestoreFrom -and ![string]::IsNullOrWhiteSpace($RestoreFrom.Id)) { $RestoreFrom.Id } else { (New-Guid).Guid }
        $DisplayName = if ($null -ne $RestoreFrom -and ![string]::IsNullOrWhiteSpace($RestoreFrom.DisplayName)) { $RestoreFrom.DisplayName } else { Get-DefaultTabDisplayName }

        # Monotonic open-order counter drives the "Query{#}" fallback name (first opened tab =
        # Query1). It only ever increments, so closing/reopening tabs never reuses a number.
        if ($null -eq $Script:TabOpenCounter) {
            $Script:TabOpenCounter = 0
        }
        $Script:TabOpenCounter++
        $OpenOrder = $Script:TabOpenCounter

        $XamlPath = Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\MainFormTabContent.xaml"
        # Initialize-FormObject's -Xaml path builds an XmlNamespaceManager off $Xaml.NameTable,
        # which only exists on an [xml] document - a plain string here fails with "constructor
        # not found" for XmlNamespaceManager.
        [xml]$Xaml = Get-Content -Path $XamlPath -Raw
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
            OpenOrder        = $OpenOrder
            # Set true after the first Update-TabHeaderTitle paint so a rename is only logged for
            # genuine post-creation name changes, not the initial default-to-derived assignment.
            HeaderInitialized = $false
            PendingEditorText = $null
            PendingDisplayName = $null
            # A restored/auto-connected tab's first Set-EditorValue push (from
            # Initialize-WebViewForTab's NavigationCompleted handler) can run while this tab is
            # backgrounded - a later tab in the same restore loop, or the persisted active tab, is
            # what actually ends up selected. That push does not reliably show up once the tab is
            # later selected on its own. NeedsEditorSync stays true until a Set-EditorValue push
            # happens while this tab is genuinely the selected one (see Initialize-WebViewForTab.ps1
            # and MainForm.Elements.TabControlSessions.ps1), so the tab-switch handler knows to force
            # exactly one fresh push the first time the user actually looks at this tab.
            NeedsEditorSync  = $true
            # Lazy-load state: a -Deferred (restored) tab is created without its WebView2 or
            # connection; Complete-TabMaterialization builds those the first time the tab is viewed.
            # PendingAutoConnect carries the restore-time "reconnect all?" answer until then.
            IsMaterialized     = $false
            PendingAutoConnect = $false
            IsDirty          = $false
            Form             = $Form
            Elements         = $Form.Elements
            TabItem          = $null
            ConnectionStatus = $false
            PendingTask      = $null
            # The "Executing Query..." window, per tab. Module scope is what it used to be, and that
            # made one tab's popup appear over every other tab and leaked a window that nothing could
            # close once a second tab started a query. See Show-ExecuteQueryPopup.
            ExecutePopup     = $null
            CurrentUrl       = $null
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
        $TabItem.ContextMenu = New-TabContextMenu -TabSession $NewTab
        # Tag carries the tab id so the drag-reorder handlers (plain scriptblocks, no GetNewClosure)
        # can identify source/target tabs from their senders.
        $TabItem.Tag = $NewTab.Id
        $TabItem.AllowDrop = $true
        $TabItem.Add_PreviewMouseLeftButtonDown({
                $Script:TabDragStartPoint = $_.GetPosition($null)
                $Script:TabDragArmed = $true
            })
        $TabItem.Add_PreviewMouseMove({
                param($DragSender, $DragArgs)
                try {
                    if ($DragArgs.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed -and $Script:TabDragArmed) {
                        # The tab CONTENT is a visual descendant of the TabItem, so this handler also
                        # fires for mouse moves inside a field. Only drag when the gesture is on the
                        # tab HEADER - walk the visual tree up from the element under the pointer to
                        # the TabItem's Header; if we reach the TabItem first it is content, so bail
                        # and let the field handle the drag as a normal text selection.
                        $Node = $DragArgs.OriginalSource
                        $Header = $DragSender.Header
                        $OnHeader = $false
                        while ($null -ne $Node) {
                            if ($Node -eq $Header) {
                                $OnHeader = $true
                                break
                            }
                            if ($Node -eq $DragSender -or ($Node -isnot [System.Windows.Media.Visual] -and $Node -isnot [System.Windows.Media.Media3D.Visual3D])) {
                                break
                            }
                            $Node = [System.Windows.Media.VisualTreeHelper]::GetParent($Node)
                        }
                        if (-not $OnHeader) {
                            return
                        }

                        $Position = $DragArgs.GetPosition($null)
                        $DeltaX = [Math]::Abs($Position.X - $Script:TabDragStartPoint.X)
                        $DeltaY = [Math]::Abs($Position.Y - $Script:TabDragStartPoint.Y)
                        if ($DeltaX -gt [System.Windows.SystemParameters]::MinimumHorizontalDragDistance -or $DeltaY -gt [System.Windows.SystemParameters]::MinimumVerticalDragDistance) {
                            $Script:TabDragArmed = $false
                            # Carry the tab id under a private format, NOT as plain text. A raw string
                            # would be a droppable text payload that any TextBox (or the app at large)
                            # accepts and pastes on release - dropping the tab's GUID into fields. Only
                            # the tab Drop/DragOver handlers below recognise "OmadaTabDragId".
                            $DragData = New-Object System.Windows.DataObject
                            $DragData.SetData("OmadaTabDragId", [string]$DragSender.Tag)
                            [void][System.Windows.DragDrop]::DoDragDrop($DragSender, $DragData, [System.Windows.DragDropEffects]::Move)
                        }
                    }
                }
                catch {
                    $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            })
        $TabItem.Add_DragOver({
                try {
                    # Only a tab drag (our private format) may be dropped on a tab; anything else shows
                    # "no drop" so, e.g., text dragged from elsewhere cannot land on the tab strip.
                    $DragOverArgs = $_
                    if ($DragOverArgs.Data.GetDataPresent("OmadaTabDragId")) {
                        $DragOverArgs.Effects = [System.Windows.DragDropEffects]::Move
                    }
                    else {
                        $DragOverArgs.Effects = [System.Windows.DragDropEffects]::None
                    }
                    $DragOverArgs.Handled = $true
                }
                catch {
                    $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            })
        $TabItem.Add_Drop({
                param($DropSender, $DropArgs)
                try {
                    if ($DropArgs.Data.GetDataPresent("OmadaTabDragId")) {
                        $DraggedId = $DropArgs.Data.GetData("OmadaTabDragId")
                        if (![string]::IsNullOrWhiteSpace($DraggedId)) {
                            Move-TabSession -DraggedTabId $DraggedId -TargetTabId $DropSender.Tag
                        }
                    }
                }
                catch {
                    $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            })
        $NewTab.TabItem = $TabItem
        Update-TabHeaderTitle -TabSession $NewTab

        $TabControlSessions = Get-TabControlSessions
        $AddNewTabItem = $TabControlSessions.Items | Where-Object { $_.Name -eq "TabItemAddNew" }
        $InsertIndex = $TabControlSessions.Items.IndexOf($AddNewTabItem)
        if ($InsertIndex -lt 0) {
            [void]$TabControlSessions.Items.Add($TabItem)
        }
        else {
            $TabControlSessions.Items.Insert($InsertIndex, $TabItem)
        }

        $Script:Tabs.Add($NewTab)

        # Selecting the new TabItem fires TabControlSessions' SelectionChanged synchronously,
        # which calls Set-ActiveTabContext -TabSession $NewTab - from this point on,
        # $Script:MainForm.Elements/$Script:AppConfig/$Script:RunTimeData/etc. all refer to $NewTab.
        # (TabControlSessions itself must always be resolved via Get-TabControlSessions, not
        # $Script:MainForm.Elements - the latter is what's about to be repointed away from it.)
        # Selecting the new tab fires TabControlSessions' SelectionChanged synchronously (activating
        # it). Suppress the NeedsEditorSync editor re-push during THIS transient creation-time
        # selection: the tab's Monaco is not realized yet, so a push now is lost AND would wrongly
        # clear NeedsEditorSync - which is exactly what left background restored tabs blank until
        # Refresh. Keeping the flag true means the first REAL user selection re-pushes the query once
        # the editor exists.
        $Script:SuppressEditorSync = $true
        try {
            $TabControlSessions.SelectedItem = $TabItem
        }
        finally {
            $Script:SuppressEditorSync = $false
        }

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
            # SelectedItem (not SelectedValue) - Test-ConnectionSettings reads SelectedItem
            # directly to decide the authentication option for Test-ShouldConnect. Leaving this as
            # SelectedValue meant that check saw a null AuthenticationOption after a restored/
            # auto-connected tab's auth genuinely succeeded, so Test-ShouldConnect incorrectly
            # returned false and Set-SqlConnectionState -Status $false ran right after - re-enabling
            # the connection fields and leaving the Connect button showing "Connect" even though the
            # tab was actually authenticated (query list/editor worked because that runs off the
            # separate, already-successful Test-OmadaConnection result).
            $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem = $Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.Items | Where-Object { $_.Content -eq $Script:AppConfig.LastAuthentication }
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

        # The reconnect answer for this tab; honoured now (eager) or on first view (deferred).
        $NewTab.PendingAutoConnect = [bool]$AutoConnect

        if ($Deferred) {
            # Lazy tab: show the disconnected shell now and stop here. The reconnect and the
            # WebView2/Monaco init are deferred to Complete-TabMaterialization, run the first time
            # this tab is actually selected (see MainForm.Elements.TabControlSessions.ps1).
            Set-SqlConnectionState -Status $false
        }
        else {
            # Interactively-created / migrated / active-restore tab: bring it fully to life now.
            Complete-TabMaterialization -TabSession $NewTab
        }

        return $NewTab
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
