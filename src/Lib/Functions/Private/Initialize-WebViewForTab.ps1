function Initialize-WebViewForTab {
    <#
    .SYNOPSIS
    Sets up the WebView2/Monaco editor for one tab: resolves the WebView2 runtime, creates (or
    reuses) the shared CoreWebView2Environment, loads Monaco, and wires the editor's keyboard
    shortcuts and web-message handlers. Factored out of the single global setup that used to run
    once in MainForm.Definition.ps1's Add_Loaded, so it can run once per tab instead.

    .NOTES
    The EnsureCoreWebView2Async completion logic is enqueued onto
    $Script:PendingWebViewCompletions rather than run from a scriptblock created in this
    function's own call frame - see the WebViewCompletionPollTimer comment in
    MainForm.Definition.ps1 for why. The shared top-level timer calls Set-ActiveTabContext for
    the originating tab before invoking that scriptblock, and restores the previously-active tab
    afterward, so the enqueued logic can always assume $TabSession is the active context. The
    completion block receives the owning tab through the enqueued completion item ($Completion.
    TabSession) instead of capturing it, so it stays a plain scriptblock that can resolve this
    module's private functions. The nested PreviewKeyDown/WebMessageReceived/NavigationCompleted
    handlers are likewise plain scriptblocks (they run long after this block returns, so they
    genuinely are independent WPF/WebView2 events); each recovers its owning tab from the event
    sender via Get-TabSessionByWebViewSender and calls Set-ActiveTabContext itself. None of these
    may use GetNewClosure(): a closure runs in a detached dynamic module that cannot see this
    module's dot-sourced private functions, which throws CommandNotFoundException.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        $TabSession.WebView.Object = $TabSession.Elements.webView21
        if ($null -eq $TabSession.WebView.Object) {
            "Failed to find WebView2 control for tab '{0}'." -f $TabSession.DisplayName | Write-LogOutput -LogType ERROR
            return
        }

        $SharedUserDataFolder = Join-Path $Env:TEMP -ChildPath "OmadaSqlTroubleshooter"
        if (-not (Test-Path -Path $SharedUserDataFolder)) {
            New-Item -Path $SharedUserDataFolder -ItemType Directory -Force | Out-Null
        }
        $TabSession.WebView.UserDataFolder = $SharedUserDataFolder

        $TabSession.WebView.EdgeWebview2RuntimePath = Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "bin\Webview2Runtime"
        if (!(Test-Path ($TabSession.WebView.EdgeWebview2RuntimePath) -PathType Container)) {
            $TabSession.WebView.EdgeWebview2RuntimePath = Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)) -ChildPath "OmadaSqlTroubleShooter\bin\Webview2Runtime"
        }

        # The Monaco WebView2 only ever hosts the local editor HTML (never Omada auth), so one
        # shared CoreWebView2Environment/profile across all tabs is correct - no reason to pay
        # for N separate environments the way Omada's own auth WebView2 does.
        if ($null -eq $Script:SharedWebViewEnvironment) {
            if ((Test-Path -Path $TabSession.WebView.EdgeWebview2RuntimePath -PathType Container) -and (Test-Path -Path (Join-Path $TabSession.WebView.EdgeWebview2RuntimePath -ChildPath "msedgewebview2.exe") -PathType Leaf)) {
                $Script:SharedWebViewEnvironment = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($TabSession.WebView.EdgeWebview2RuntimePath, $SharedUserDataFolder).GetAwaiter().GetResult()
            }
            else {
                $Script:SharedWebViewEnvironment = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $SharedUserDataFolder).GetAwaiter().GetResult()
            }
        }
        $TabSession.WebView.Environment = $Script:SharedWebViewEnvironment

        if (-not (Test-Path $Script:WebView2UserProfilePath -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $Script:WebView2UserProfilePath | Out-Null
        }

        $EnsureCoreWebView2Task = $TabSession.WebView.Object.EnsureCoreWebView2Async($TabSession.WebView.Environment)

        # This completion block is enqueued for the top-level WebViewCompletionPollTimer in
        # MainForm.Definition.ps1 to invoke once EnsureCoreWebView2Async finishes. It MUST be a
        # plain scriptblock (with a param) rather than a .GetNewClosure() block: a GetNewClosure()
        # block runs inside a detached dynamic module whose scope does not include this module's
        # dot-sourced private functions, so its very first Write-LogOutput call throws
        # CommandNotFoundException and the whole Monaco setup silently fails. A plain block keeps
        # this module's session state (private functions resolve), and the owning tab is passed in
        # via the enqueued completion item instead of captured by reference.
        $OnCompletedScriptBlock = {
                param($Completion)
                $TabSession = $Completion.TabSession
                try {
                    "EnsureCoreWebView2Async OnCompleted script for tab '{0}'" -f $TabSession.DisplayName | Write-LogOutput -LogType DEBUG

                    # This scriptblock only ever runs invoked from the top-level
                    # WebViewCompletionPollTimer's Tick handler in MainForm.Definition.ps1, which
                    # is itself always on the UI thread (DispatcherTimer.Tick fires on the thread
                    # of the Dispatcher it belongs to) - wrapping these UI mutations in
                    # Dispatcher.Invoke would be redundant and would only add another needless
                    # reentrancy window (a Dispatcher.Invoke also pumps this thread's messages
                    # while it blocks, same risk class as the modal-dialog reentrancy documented
                    # in Suspend-WebViewCompletionPolling.ps1).
                    if ($null -eq $TabSession.WebView.Object.CoreWebView2) {
                        $Message = "WebView2 environment initialization failed. If this system does not have the Webview2 Runtime installed, please download the fixed version from https://developer.microsoft.com/en-us/microsoft-edge/webview2/ and extract the cab file to folder '{0}'" -f $TabSession.WebView.EdgeWebview2RuntimePath
                        $Message | Write-LogOutput -LogType ERROR
                        return
                    }

                    $HtmlFile = Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "Monaco\index.html"
                    if ([System.IO.File]::Exists($HtmlFile)) {
                        $TabSession.WebView.Object.Source = New-Object System.Uri($HtmlFile)
                        "WebView source set to: {0}" -f $HtmlFile | Write-LogOutput -LogType DEBUG
                    }
                    else {
                        "Monaco HTML file not found at: {0}" -f $HtmlFile | Write-LogOutput -LogType ERROR
                    }

                    Test-ConnectionButton

                    # Refreshing the query list is an authenticated round-trip AND it re-enables
                    # ComboBoxSelectQuery / ButtonRefreshQueries / the "my queries" checkboxes
                    # unconditionally at the end of Update-QueryList. Running it for a tab that was
                    # deliberately left disconnected (a restored tab under -NoReconnect, or after a
                    # declined reconnect prompt) therefore both connected to the tenant and undid the
                    # Set-SqlQueryFunctionState -Status $false that Complete-TabMaterialization had
                    # just applied - which is why such a tab showed an openable query dropdown next
                    # to a Connect button. Only refresh it for a tab that genuinely connected.
                    if ($Script:ConnectionStatus) {
                        Update-QueryList
                    }

                    Set-EditorValue

                    # These WebView2 event handlers fire independently, long after this completion
                    # block has returned, so they cannot capture $TabSession by reference. They are
                    # plain scriptblocks (NOT .GetNewClosure()) so they keep this module's session
                    # state and can resolve its private functions; each recovers its owning tab
                    # from the event sender via Get-TabSessionByWebViewSender.
                    $TabSession.WebView.Object.add_PreviewKeyDown({
                            param($KeyEventSender, $KeyEventArgs)
                            try {
                                $_ | Show-EventInfo
                                $HandlerTab = Get-TabSessionByWebViewSender -Sender $KeyEventSender
                                if ($null -eq $HandlerTab) {
                                    return
                                }
                                # Skip auto-repeats so a held key is not logged over and over.
                                if (-not $KeyEventArgs.IsRepeat) {
                                    "PreviewKeyDown on {0} for tab '{1}'" -f $KeyEventSender.GetType().Name, $HandlerTab.DisplayName | Write-LogOutput -LogType VERBOSE2
                                }

                                $CtrlDown = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control
                                $ShiftDown = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift

                                if ($KeyEventArgs.Key -eq [System.Windows.Input.Key]::S -and $CtrlDown -and -not $ShiftDown) {
                                    "Ctrl+S key intercepted in WebView2 (PreviewKeyDown) for tab '{0}'" -f $HandlerTab.DisplayName | Write-LogOutput -LogType DEBUG
                                    $KeyEventArgs.Handled = $true

                                    $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                                            Set-ActiveTabContext -TabSession $HandlerTab
                                            "Triggering Save Query from Ctrl+S key press" | Write-LogOutput -LogType DEBUG
                                            $Script:MainForm.Elements.ButtonSaveQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                                        })
                                }
                                elseif ($KeyEventArgs.Key -eq [System.Windows.Input.Key]::K -and $CtrlDown -and $ShiftDown) {
                                    "Ctrl+Shift+K key intercepted in WebView2 - duplicate tab '{0}'" -f $HandlerTab.DisplayName | Write-LogOutput -LogType DEBUG
                                    $KeyEventArgs.Handled = $true
                                    $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                                            Invoke-DuplicateTab -TabId $HandlerTab.Id
                                        })
                                }
                                elseif ($KeyEventArgs.Key -eq [System.Windows.Input.Key]::T -and $CtrlDown -and -not $ShiftDown) {
                                    "Ctrl+T key intercepted in WebView2 - duplicate tab without query '{0}'" -f $HandlerTab.DisplayName | Write-LogOutput -LogType DEBUG
                                    $KeyEventArgs.Handled = $true
                                    $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                                            Invoke-DuplicateTab -TabId $HandlerTab.Id -WithoutQuery
                                        })
                                }
                                elseif ($KeyEventArgs.Key -eq [System.Windows.Input.Key]::Tab -and $CtrlDown) {
                                    "Ctrl+Tab / Ctrl+Shift+Tab intercepted in WebView2 - cycle tabs" | Write-LogOutput -LogType DEBUG
                                    $KeyEventArgs.Handled = $true
                                    if ($ShiftDown) {
                                        $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                                                Select-AdjacentTab -Direction Previous
                                            })
                                    }
                                    else {
                                        $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                                                Select-AdjacentTab -Direction Next
                                            })
                                    }
                                }
                                elseif ($CtrlDown -and -not $ShiftDown -and ($KeyEventArgs.Key -eq [System.Windows.Input.Key]::W -or $KeyEventArgs.Key -eq [System.Windows.Input.Key]::F4)) {
                                    "Ctrl+W / Ctrl+F4 intercepted in WebView2 - close tab '{0}'" -f $HandlerTab.DisplayName | Write-LogOutput -LogType DEBUG
                                    $KeyEventArgs.Handled = $true
                                    $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                                            Close-TabSession -TabId $HandlerTab.Id
                                        })
                                }
                            }
                            catch {
                                $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                            }
                        })

                    # Log key releases inside the editor (Show-EventInfo -> "Key released: ...") so a
                    # held key traces as one press + one release rather than a flood of auto-repeats.
                    # Logging only - no shortcut logic here, so it cannot affect the PreviewKeyDown
                    # handling above.
                    $TabSession.WebView.Object.add_PreviewKeyUp({
                            try {
                                $_ | Show-EventInfo
                            }
                            catch {
                                $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                            }
                        })

                    $TabSession.WebView.Object.CoreWebView2.add_WebMessageReceived({
                            param($WebMessageSender, $WebMessageEventArgs)
                            try {
                                $_ | Show-EventInfo
                                $HandlerTab = Get-TabSessionByWebViewSender -Sender $WebMessageSender
                                if ($null -eq $HandlerTab) {
                                    return
                                }
                                "CoreWebView2.add_WebMessageReceived on {0} for tab '{1}'" -f $WebMessageSender.GetType().Name, $HandlerTab.DisplayName | Write-LogOutput -LogType DEBUG

                                $Message = Get-WebViewMessageString -MessageEventArgs $WebMessageEventArgs
                                "WebView2 message received: {0}" -f $Message | Write-LogOutput -LogType DEBUG

                                if ($Message) {
                                    $MessageObj = $Message | ConvertFrom-Json -ErrorAction SilentlyContinue
                                    if ($MessageObj -and $MessageObj.type -eq 'executeQuery') {
                                        "Execute Query requested from Monaco Editor via {0}" -f $MessageObj.key | Write-LogOutput -LogType DEBUG
                                        $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                                                Set-ActiveTabContext -TabSession $HandlerTab
                                                $Script:MainForm.Elements.ButtonExecuteQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                                            })
                                    }
                                    elseif ($MessageObj -and $MessageObj.type -eq 'saveQuery') {
                                        "Save Query requested from Monaco Editor via {0}" -f $MessageObj.key | Write-LogOutput -LogType DEBUG
                                        $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                                                Set-ActiveTabContext -TabSession $HandlerTab
                                                $Script:MainForm.Elements.ButtonSaveQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                                            })
                                    }
                                    elseif ($MessageObj -and $MessageObj.type -eq 'contentChanged') {
                                        $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                                                $HandlerTab.IsDirty = $true
                                                Update-TabHeaderTitle -TabSession $HandlerTab
                                            })
                                    }
                                }
                            }
                            catch {
                                $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                            }
                        })

                    $TabSession.WebView.Object.add_NavigationCompleted({
                            param($NavigationSender)
                            try {
                                $_ | Show-EventInfo
                                $HandlerTab = Get-TabSessionByWebViewSender -Sender $NavigationSender
                                if ($null -eq $HandlerTab) {
                                    return
                                }
                                "Set-EditorValue after loading html for tab '{0}'" -f $HandlerTab.DisplayName | Write-LogOutput -LogType DEBUG
                                $PreviouslyActiveTab = Get-ActiveTabSession
                                Set-ActiveTabContext -TabSession $HandlerTab
                                try {
                                    Set-EditorValue

                                    # Monaco only exists from this point on, so a tab that was ALREADY
                                    # connected before its editor finished loading (restored session,
                                    # duplicated tab, auto-connect) never received a setSchema push -
                                    # Invoke-ExecuteScriptAsync silently skips while the WebView is not
                                    # ready. Push it now so IntelliSense knows this database's tables and
                                    # columns. Get-SqlSchemaObject checks $Script:ConnectionStatus and
                                    # returns without any request when this tab is not connected (the
                                    # guard the previous version of this comment claimed but that did
                                    # not exist - the call authenticated against the tenant instead,
                                    # even under -NoReconnect); for a connected tab it serves the
                                    # per-pool + per-database cache, so this is normally just the push.
                                    Get-SqlSchemaObject

                                    # Only clear NeedsEditorSync if this tab was genuinely the selected/
                                    # visible one when the push above happened. Navigation can complete
                                    # while this tab is backgrounded (e.g. a still-restoring tab further
                                    # down Restore-TabSessions' loop, or one that lost the selection to the
                                    # persisted active tab) - the push does not reliably show up once the
                                    # tab is later selected on its own, so leave the flag set for
                                    # TabControlSessions' SelectionChanged handler to force one fresh push
                                    # then, when the tab is actually shown.
                                    if ((Get-TabControlSessions).SelectedItem -eq $HandlerTab.TabItem) {
                                        $HandlerTab.NeedsEditorSync = $false
                                    }

                                    # A duplicated tab carries the source tab's SQL here until its own
                                    # Monaco editor has loaded (now). Push it and clear the pending text.
                                    if (![string]::IsNullOrEmpty($HandlerTab.PendingEditorText)) {
                                        $SafeDuplicateText = $HandlerTab.PendingEditorText -replace "\\", "\\\\" -replace "`r", "\r" -replace "`n", "\n" -replace "`t", "\t" -replace "'", "\'"
                                        Push-ToEditor -ScriptToExecute ("window.setEditorValue('{0}');" -f $SafeDuplicateText)
                                        $HandlerTab.PendingEditorText = $null
                                    }

                                    # Restore a duplicated tab's Display name as the final step (an
                                    # auto-connect's Update-QueryList may have cleared it in the meantime).
                                    if (![string]::IsNullOrEmpty($HandlerTab.PendingDisplayName)) {
                                        $HandlerTab.Elements.TextBoxDisplayName.Text = $HandlerTab.PendingDisplayName
                                        $HandlerTab.PendingDisplayName = $null
                                    }

                                    $Script:RunTimeConfig.ReconnectStatus = 3
                                }
                                finally {
                                    # Navigation can complete for a BACKGROUND tab; do NOT leave the
                                    # global active-tab context pointing at it. Restore the on-screen
                                    # (selected) tab, otherwise a later Connect/Disconnect click would run
                                    # against this background tab - its button/status/fields update
                                    # off-screen while the visible tab appears stuck "Connected" (the
                                    # "cannot disconnect" bug).
                                    $VisibleTab = $Script:Tabs | Where-Object { $_.TabItem -eq (Get-TabControlSessions).SelectedItem } | Select-Object -First 1
                                    if ($null -eq $VisibleTab) {
                                        $VisibleTab = $PreviouslyActiveTab
                                    }
                                    if ($null -ne $VisibleTab -and $VisibleTab.Id -ne $HandlerTab.Id) {
                                        Set-ActiveTabContext -TabSession $VisibleTab
                                    }
                                }
                            }
                            catch {
                                $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                            }
                        })

                    "WebView2 for tab '{0}' initialized" -f $TabSession.DisplayName | Write-LogOutput -LogType DEBUG
                }
                catch {
                    "WebView2 initialization failed for tab '{0}': {1}" -f $TabSession.DisplayName, $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            }

        $Script:PendingWebViewCompletions.Add([PSCustomObject]@{
                Task                   = $EnsureCoreWebView2Task
                TabSession             = $TabSession
                OnCompletedScriptBlock = $OnCompletedScriptBlock
            })
    }
    catch {
        "WebView2 initialization failed for tab '{0}': {1}" -f $TabSession.DisplayName, $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
