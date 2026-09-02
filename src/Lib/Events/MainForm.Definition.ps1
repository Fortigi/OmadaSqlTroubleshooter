# WebView2/Monaco's async completions kept throwing CommandNotFoundException for dot-sourced
# functions. The actual cause was .GetNewClosure(): a closure runs inside a detached dynamic
# module whose scope does not include this module's private (non-exported) functions, so any
# call to Write-LogOutput/Set-EditorValue/etc. from a closure fails - no matter which .NET
# dispatch mechanism invokes it. A PLAIN scriptblock (no GetNewClosure), by contrast, keeps this
# module's session state and resolves private functions fine, even when created inside a function
# and invoked later by .NET. So the rule is: deferred/event scriptblocks must be plain blocks and
# receive their per-tab state via a parameter (or recover it from the event sender), never via
# GetNewClosure. This single top-level timer drains the completion queue; each enqueued
# OnCompletedScriptBlock is a plain block invoked with its $Pending item as the argument.
$Script:PendingWebViewCompletions = [System.Collections.Generic.List[object]]::new()

$Script:WebViewCompletionPollTimer = New-Object System.Windows.Threading.DispatcherTimer
$Script:WebViewCompletionPollTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$Script:WebViewCompletionPollTimer.Add_Tick({
        try {
            $Completed = @($Script:PendingWebViewCompletions | Where-Object { $_.Task.IsCompleted })
            foreach ($Pending in $Completed) {
                [void]$Script:PendingWebViewCompletions.Remove($Pending)

                # Get-ActiveTabSession/Set-ActiveTabContext and the enqueued OnCompletedScriptBlock
                # all run from this top-level Tick handler's frame. The OnCompletedScriptBlock is a
                # plain block (never a GetNewClosure block), so it too resolves this module's
                # private functions - it just needs its per-tab state handed to it, which is why
                # $Pending is passed as its argument below.
                #
                # A $null TabSession means the caller's own OnCompletedScriptBlock manages the
                # active-tab context itself (e.g. Close-TabSession deciding which tab becomes
                # active after teardown) - auto-repointing/restoring around it here would just
                # stomp on that decision, so skip it entirely in that case.
                # The completion block is invoked with the whole $Pending item as its argument so
                # it can be a plain scriptblock that reads its owning tab (and any other captured
                # data) from $Pending instead of a .GetNewClosure() block - the latter runs in a
                # detached dynamic module that cannot resolve this app's dot-sourced private
                # functions (CommandNotFoundException). Plain blocks without a param() simply
                # ignore the argument.
                # A completion block is optional. A caller that only pushes something into the editor
                # and has nothing to do afterwards - the syntax pass writing its markers, for
                # instance - passes none, and the item is still queued so the task is drained and
                # removed. Invoking a $null here is what "The expression after '&' in a pipeline
                # element produced an object that was not valid" means, so the queue is drained
                # either way and only a real scriptblock is called.
                $CompletedScriptBlock = $Pending.OnCompletedScriptBlock

                if (-not (Test-WebViewCompletionCallback -Callback $CompletedScriptBlock)) {
                    continue
                }

                if ($null -ne $Pending.TabSession) {
                    $PreviouslyActiveTab = Get-ActiveTabSession
                    try {
                        Set-ActiveTabContext -TabSession $Pending.TabSession
                        & $CompletedScriptBlock $Pending
                    }
                    finally {
                        if ($null -ne $PreviouslyActiveTab) {
                            Set-ActiveTabContext -TabSession $PreviouslyActiveTab
                        }
                    }
                }
                else {
                    & $CompletedScriptBlock $Pending
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
$Script:WebViewCompletionPollTimer.Start()

# Debounce timer for the editor's client-side T-SQL syntax validation (issue #61). Declared here,
# at the top level, for exactly the reason spelled out above: a DispatcherTimer whose Tick handler
# is created inside a function cannot resolve this module's dot-sourced private functions when .NET
# later invokes it. Request-SqlSyntaxValidation only restarts it; this is where it fires.
#
# It is created stopped and started on demand, so a session that never types - or one where the
# feature is switched off or the parser is unavailable - never pays for a running timer.
$Script:SqlValidationPendingTabId = $null
$Script:SqlValidationDebounceTimer = New-Object System.Windows.Threading.DispatcherTimer
$Script:SqlValidationDebounceTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$Script:SqlValidationDebounceTimer.Add_Tick({
        try {
            # One-shot: the timer is restarted by the next content change, not by itself.
            $Script:SqlValidationDebounceTimer.Stop()

            $PendingTab = $null
            if (![string]::IsNullOrWhiteSpace($Script:SqlValidationPendingTabId)) {
                $PendingTab = $Script:Tabs | Where-Object { $_.Id -eq $Script:SqlValidationPendingTabId } | Select-Object -First 1
            }

            if ($null -eq $PendingTab) {
                return
            }

            # Validate the tab that actually changed, restoring whatever tab the user is looking at
            # now - the same discipline the completion poll timer above follows.
            $PreviouslyActiveTab = Get-ActiveTabSession
            try {
                Set-ActiveTabContext -TabSession $PendingTab
                Update-SqlSyntaxDiagnostic
            }
            finally {
                if ($null -ne $PreviouslyActiveTab) {
                    Set-ActiveTabContext -TabSession $PreviouslyActiveTab
                }
            }
        }
        catch {
            # Validation is a convenience. A failure here is logged at DEBUG and nothing else: it
            # must never interrupt typing, and the message can quote the query.
            "Debounced syntax validation failed." | Write-LogOutput -LogType DEBUG
        }
    })

# Host the session tabs in the single-row ShrinkingTabPanel (defined in
# Initialize-OmadaSqlTroubleShooter) so they shrink to fit on one row - with ellipsised text -
# instead of wrapping onto a second row. Set here in code because the type is added at runtime and
# so cannot be referenced from the XAML namespace.
try {
    $TabStripPanelFactory = New-Object System.Windows.FrameworkElementFactory([Fortigi.ShrinkingTabPanel])
    (Get-TabControlSessions).ItemsPanel = New-Object System.Windows.Controls.ItemsPanelTemplate($TabStripPanelFactory)
}
catch {
    "Failed to set the single-row tab panel: {0}" -f $_.Exception.Message | Write-LogOutput -LogType WARNING
}

# The "+" add tab opens a new tab ONLY on an explicit click. Handling it here (and marking the
# event Handled so "+" is never actually selected) is what keeps a new tab from appearing whenever
# WPF selects "+" for a non-user reason - window activation/focus, relayout, or a tab close moving
# the selection. Wired in code because TabItemAddNew is not exposed via $Script:MainForm.Elements.
try {
    $AddNewTabItem = (Get-TabControlSessions).Items | Where-Object { $_.Name -eq "TabItemAddNew" } | Select-Object -First 1
    if ($null -ne $AddNewTabItem) {
        $AddNewTabItem.Add_PreviewMouseLeftButtonDown({
                param($AddTabSender, $AddTabArgs)
                try {
                    $AddTabArgs.Handled = $true
                    New-EmptyTabSession | Out-Null
                }
                catch {
                    $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            })
    }
}
catch {
    "Failed to wire the '+' add-tab click handler: {0}" -f $_.Exception.Message | Write-LogOutput -LogType WARNING
}

$Script:MainForm.Definition.Add_Closed({
        try {
            $_ | Show-EventInfo
            $Script:MainForm.State = "Closed"
            $Script:MainForm.Definition.Close()
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Definition.Add_Closing({
        try {
            $_ | Show-EventInfo
            $Script:MainForm.State = "Closing"
            Save-TabSessions
            Save-FormMeasurements
            if (Test-LogFormIsVisible) {
                $Script:LogForm.Definition.Close()
            }
            if (Test-SqlHistoryFormOpen) {
                $Script:SqlHistoryForm.Definition.Close()
            }
            if (Test-SqlSchemaFormIsVisible) {
                $Script:SqlSchemaForm.Definition.Close()
            }

            # Background request workers are real threads; left open they keep the process alive
            # after the window has gone (issue #40). Best-effort, and last, so a failure here cannot
            # cost the user their saved tab sessions or window measurements above.
            Close-OmadaRequestPool
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

# Second half of the Home/End fix (first half: the TabControl class handler in
# Initialize-OmadaSqltroubleShooter). That handler marks Home/End handled so the TabControl cannot
# jump to the first/last tab - but WebView2 only forwards a key to Monaco when the WPF routed event
# returns UNhandled, so leaving it handled would stop the caret moving instead. By here the bubble
# has passed the TabControl and it can no longer act on the key, so hand it back to the editor.
# handledEventsToo is required: the event is handled at this point, which is exactly why we are here.
$Script:MainForm.Definition.AddHandler(
    [System.Windows.Input.Keyboard]::KeyDownEvent,
    [System.Windows.Input.KeyEventHandler] {
        param(
            $EventSender,
            $EventArgs
        )
        if ((Test-EditorNavigationKey -KeyName ([string]$EventArgs.Key)) -and $EventArgs.OriginalSource -is [Microsoft.Web.WebView2.Wpf.WebView2]) {
            $EventArgs.Handled = $false
        }
    },
    $true)

$Script:MainForm.Definition.Add_PreviewKeyDown({
        param(
            $EventSender,
            $EventArgs
        )
        try {
            $_ | Show-EventInfo

            $ControlPressed = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control
            $ShiftPressed = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift

            if ($EventArgs.Key -eq [System.Windows.Input.Key]::F5) {
                # When the WebView2 (Monaco editor) has focus, let Monaco handle F5 via postMessage
                # so it can include selection information for "execute selection" behaviour.
                # Only intercept here when focus is outside the WebView2.
                if ($null -ne $Script:Webview.Object -and $Script:Webview.Object.IsKeyboardFocusWithin) {
                    "F5 key at MainForm level - WebView2 has focus, deferring to Monaco" | Write-LogOutput -LogType VERBOSE
                }
                else {
                    "F5 key intercepted at MainForm level" | Write-LogOutput -LogType VERBOSE

                    $EventArgs.Handled = $true

                    "Triggering Execute Query from F5 key press (MainForm)" | Write-LogOutput -LogType VERBOSE
                    $Script:MainForm.Elements.ButtonExecuteQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                }
            }
            elseif ($ControlPressed -and $EventArgs.Key -eq [System.Windows.Input.Key]::Tab) {
                $EventArgs.Handled = $true
                if ($ShiftPressed) {
                    "Ctrl+Shift+Tab intercepted at MainForm level - select previous tab" | Write-LogOutput -LogType VERBOSE
                    Select-AdjacentTab -Direction Previous
                }
                else {
                    "Ctrl+Tab intercepted at MainForm level - select next tab" | Write-LogOutput -LogType VERBOSE
                    Select-AdjacentTab -Direction Next
                }
            }
            elseif ($EventArgs.Key -eq [System.Windows.Input.Key]::S -and $ControlPressed -and -not $ShiftPressed) {
                "Ctrl+S key intercepted at MainForm level" | Write-LogOutput -LogType VERBOSE

                $EventArgs.Handled = $true

                "Triggering Save Query from Ctrl+S key press (MainForm)" | Write-LogOutput -LogType VERBOSE
                $Script:MainForm.Elements.ButtonSaveQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
            }
            elseif ($EventArgs.Key -eq [System.Windows.Input.Key]::C -and $ControlPressed -and -not $ShiftPressed) {
                # Allow Ctrl+C to pass through to DataGrid - do NOT handle it here
                "Ctrl+C detected at MainForm level - allowing to pass through to focused control" | Write-LogOutput -LogType VERBOSE
                # Do not set $EventArgs.Handled = $true for Ctrl+C
            }
            elseif ($ControlPressed -and $ShiftPressed -and $EventArgs.Key -eq [System.Windows.Input.Key]::K) {
                "Ctrl+Shift+K intercepted at MainForm level - duplicate active tab" | Write-LogOutput -LogType VERBOSE
                $EventArgs.Handled = $true
                $ActiveTab = Get-ActiveTabSession
                if ($null -ne $ActiveTab) {
                    Invoke-DuplicateTab -TabId $ActiveTab.Id
                }
            }
            elseif ($ControlPressed -and -not $ShiftPressed -and $EventArgs.Key -eq [System.Windows.Input.Key]::T) {
                "Ctrl+T intercepted at MainForm level - duplicate active tab without query" | Write-LogOutput -LogType VERBOSE
                $EventArgs.Handled = $true
                $ActiveTab = Get-ActiveTabSession
                if ($null -ne $ActiveTab) {
                    Invoke-DuplicateTab -TabId $ActiveTab.Id -WithoutQuery
                }
            }
            elseif ($ControlPressed -and -not $ShiftPressed -and ($EventArgs.Key -eq [System.Windows.Input.Key]::W -or $EventArgs.Key -eq [System.Windows.Input.Key]::F4)) {
                "Ctrl+W / Ctrl+F4 intercepted at MainForm level - close active tab" | Write-LogOutput -LogType VERBOSE
                $EventArgs.Handled = $true
                $ActiveTab = Get-ActiveTabSession
                if ($null -ne $ActiveTab) {
                    Close-TabSession -TabId $ActiveTab.Id
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

# Log key releases (Show-EventInfo -> "Key released: ...") so a held key is traced as one press and
# one release instead of a flood of auto-repeat PreviewKeyDown lines. Logging only - no shortcut
# logic lives here, so it cannot affect any existing key handling.
$Script:MainForm.Definition.Add_PreviewKeyUp({
        try {
            $_ | Show-EventInfo
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Definition.Add_Loaded({
        try {
            $_ | Show-EventInfo

            # Flip to "Open" before anything else in this handler runs: TabControlSessions'
            # SelectionChanged guards on this state to reject the reentrant selection WPF fires
            # for TabItemAddNew as soon as the control materializes (before Loaded even starts) -
            # but Restore-TabSessions below still needs to run with State already "Open", since it
            # selects each restored TabItem synchronously through that same SelectionChanged handler.
            $Script:MainForm.State = "Open"

            if ($Script:AppGlobalConfig.LogFormOpen) {
                Open-LogForm
            }

            if ($null -ne ($Script:MainForm.Definition | Get-FormPositionConfig)) {
                $Position = $Script:MainForm.Definition | Get-FormPositionConfig
                "Main form position: {0}" -f $Position | Write-LogOutput -LogType DEBUG
                $Script:MainForm.Definition.Left = [Int]::Abs($Position.Split("x")[0])
                $Script:MainForm.Definition.Top = [Int]::Abs($Position.Split("x")[1])
            }
            if ($null -ne ($Script:MainForm.Definition | Get-FormSizeConfig)) {
                $Size = $Script:MainForm.Definition | Get-FormSizeConfig
                "Main form size: {0}" -f $Size | Write-LogOutput -LogType DEBUG
                $Script:MainForm.Definition.Width = [Int]::Abs($Size.Split("x")[0])
                $Script:MainForm.Definition.Height = [Int]::Abs($Size.Split("x")[1])
            }

            # Per-tab WebView2 setup (runtime resolution, shared CoreWebView2Environment, Monaco
            # load, keyboard shortcuts, web-message handling) now happens once per tab inside
            # New-TabSession -> Initialize-WebViewForTab, not once globally here. Restore-TabSessions
            # creates the initial tab(s) - from persisted state, migrated legacy config, or a
            # single fresh tab on first-ever run.
            Restore-TabSessions
        }
        catch {
            "Tab session restore failed: {0}" -f $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

$Script:MainForm.Definition.Add_LocationChanged({
        try {
            $_ | Show-EventInfo -LogType VERBOSE2

            $ActionId = [System.Guid]::NewGuid().ToString()

            if (!$Script:MainForm.Definition.IsVisible -or $Script:MainForm.Definition.Left -lt 0 -or $Script:MainForm.Definition.Top -lt 0) {
                "MainForm is not suitable for processing. Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:MainForm.Definition.Left, $Script:MainForm.Definition.Top, $Script:MainForm.Definition.Width , $Script:MainForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
                return
            }

            "MainForm Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:MainForm.Definition.Left, $Script:MainForm.Definition.Top, $Script:MainForm.Definition.Width , $Script:MainForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
            if ((Test-LogFormIsVisible) -and -not $Script:LogForm.PositionManager.Synchronizing) {
                if ($Script:LogForm.Definition.Left -lt 0 -or $Script:LogForm.Definition.Top -lt 0) {
                    "LogForm is not suitable for processing. Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:MainForm.Definition.Left, $Script:MainForm.Definition.Top, $Script:MainForm.Definition.Width , $Script:MainForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
                    return
                }
                "LogForm Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:LogForm.Definition.Left, $Script:LogForm.Definition.Top, $Script:LogForm.Definition.Width , $Script:LogForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
                $Script:LogForm.PositionManager.Synchronizing = $true
                $Script:MainForm.Definition.Dispatcher.Invoke({
                        $Script:LogForm.Definition.Left = [Int]::Abs($Script:MainForm.Definition.Left) + [Int]::Abs($Script:LogForm.PositionManager.PositionOffSetLeft)
                        $Script:LogForm.Definition.Top = [Int]::Abs($Script:MainForm.Definition.Top) + [Int]::Abs($Script:LogForm.PositionManager.PositionOffSetTop)
                        "LogForm Position: {0}x{1}, Dimensions: {2}x{3}, PositionManagerOffSet: {4}x{5} (Id:{6})" -f $Script:LogForm.Definition.Left, $Script:LogForm.Definition.Top, $Script:LogForm.Definition.Width , $Script:LogForm.Definition.Height, $Script:LogForm.PositionManager.PositionOffSetLeft, $Script:LogForm.PositionManager.PositionOffSetTop, $ActionId | Write-LogOutput -LogType VERBOSE2
                        $Script:LogForm.PositionManager.Synchronizing = $false
                    }, [System.Windows.Threading.DispatcherPriority]::Render)
            }
            if ((Test-SqlSchemaFormIsVisible) -and -not $Script:SqlSchemaForm.PositionManager.Synchronizing) {
                $_ | Show-EventInfo -LogType VERBOSE2
                if ($Script:SqlSchemaForm.Definition.Left -lt 0 -or $Script:SqlSchemaForm.Definition.Top -lt 0) {
                    "SqlSchemaForm is not suitable for processing. Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:SqlSchemaForm.Definition.Left, $Script:SqlSchemaForm.Definition.Top, $Script:SqlSchemaForm.Definition.Width , $Script:SqlSchemaForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
                    return
                }
                "SqlSchemaForm Position: {0}x{1}, Dimensions: {2}x{3} (Id:{4})" -f $Script:SqlSchemaForm.Definition.Left, $Script:SqlSchemaForm.Definition.Top, $Script:SqlSchemaForm.Definition.Width , $Script:SqlSchemaForm.Definition.Height, $ActionId | Write-LogOutput -LogType VERBOSE2
                $Script:SqlSchemaForm.PositionManager.Synchronizing = $true
                $Script:MainForm.Definition.Dispatcher.Invoke({
                        $Script:SqlSchemaForm.Definition.Left = [Int]::Abs($Script:MainForm.Definition.Left) - [Int]::Abs($Script:SqlSchemaForm.PositionManager.PositionOffSetLeft)
                        $Script:SqlSchemaForm.Definition.Top = [Int]::Abs($Script:MainForm.Definition.Top) - [Int]::Abs($Script:SqlSchemaForm.PositionManager.PositionOffSetTop)
                        "SqlSchemaForm Position: {0}x{1}, Dimensions: {2}x{3}, PositionManagerOffSet: {4}x{5} (Id:{6})" -f $Script:SqlSchemaForm.Definition.Left, $Script:SqlSchemaForm.Definition.Top, $Script:SqlSchemaForm.Definition.Width, $Script:SqlSchemaForm.Definition.Height, $Script:SqlSchemaForm.PositionManager.PositionOffSetLeft, $Script:SqlSchemaForm.PositionManager.PositionOffSetTop, $ActionId | Write-LogOutput -LogType VERBOSE2
                        $Script:SqlSchemaForm.PositionManager.Synchronizing = $false
                    }, [System.Windows.Threading.DispatcherPriority]::Render)
            }
        }
        catch {
            #[System.Windows.MessageBox]::Show("WebView2 initialization failed: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
            "WebView2 initialization failed: {0}" -f $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

#Find out if still needed
#$Script:MainForm.Definition.Add_SizeChanged({
#        $_ | Show-EventInfo -LogType VERBOSE2
#        if ((Test-LogFormIsVisible) -and -not $Script:LogForm.PositionManager.Synchronizing) {
#            $Script:LogForm.PositionManager.Synchronizing = $true
#            $Script:MainForm.Definition.Dispatcher.Invoke({
#                    Update-LogFormPosition
#                }, [System.Windows.Threading.DispatcherPriority]::Render)
#        }
#    })
