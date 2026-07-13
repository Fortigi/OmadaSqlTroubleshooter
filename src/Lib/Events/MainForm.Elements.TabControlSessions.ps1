(Get-TabControlSessions).Add_SelectionChanged({
        param(
            $EventSender,
            $EventArgs
        )
        try {
            $_ | Show-EventInfo

            # WPF's TabControl re-selects its first item (TabItemAddNew) as soon as the control
            # materializes - even with SelectedIndex="-1" in XAML - which happens before
            # MainForm.Definition's Add_Loaded runs. Reject that reentrant firing: it would call
            # New-TabSession against a MainForm that is still mid-construction and crash the
            # dispatcher. $Script:MainForm.State only becomes "Open" once Add_Loaded starts.
            if ($Script:MainForm.State -ne "Open") {
                return
            }

            # Selector.SelectionChanged bubbles: a ComboBox changing selection anywhere inside a
            # tab's own content re-fires this same handler with $EventArgs.OriginalSource pointing
            # at that ComboBox, not the TabControl. Without this check, every such unrelated
            # selection change would redundantly re-run Set-ActiveTabContext/Initialize-
            # UiComponents against the already-active tab.
            if ($EventArgs.OriginalSource -ne (Get-TabControlSessions)) {
                return
            }

            $SelectedItem = (Get-TabControlSessions).SelectedItem
            if ($null -eq $SelectedItem) {
                return
            }

            if ($SelectedItem.Name -eq "TabItemAddNew") {
                # The "+" tab is not a real tab, and a selection change must NEVER create one:
                # WPF selects "+" for all sorts of non-user reasons (window activation/focus,
                # relayout, a tab close moving the selection), and creating a tab for each of those
                # caused new tabs to appear on refocus / on teardown. New tabs are opened ONLY by an
                # explicit click on "+" (its PreviewMouseLeftButtonDown handler in MainForm.
                # Definition). Here, just steer the selection back onto a real tab so "+" is never
                # left selected.
                $CurrentTab = Get-ActiveTabSession
                if ($null -ne $CurrentTab -and $null -ne $CurrentTab.TabItem) {
                    (Get-TabControlSessions).SelectedItem = $CurrentTab.TabItem
                }
                else {
                    (Get-TabControlSessions).SelectedIndex = -1
                }
                return
            }

            # -First 1 guarantees a single object (or $null) rather than a collection, matching
            # Get-ActiveTabSession's own convention for this exact pattern.
            $TabSession = $Script:Tabs | Where-Object { $_.TabItem -eq $SelectedItem } | Select-Object -First 1
            if ($null -ne $TabSession) {
                Set-ActiveTabContext -TabSession $TabSession

                # First real selection of a lazily-restored (deferred) tab: build its WebView2/Monaco
                # editor and reconnect now. Guarded by SuppressEditorSync so the transient
                # creation-time selection inside New-TabSession never triggers it (that tab's Monaco is
                # not realized yet). The active restored tab is materialized explicitly in
                # Restore-TabSessions; every other tab materializes here the first time it is viewed.
                # Complete-TabMaterialization is idempotent.
                if (-not $Script:SuppressEditorSync -and -not $TabSession.IsMaterialized) {
                    Complete-TabMaterialization -TabSession $TabSession
                }

                # This tab's first Set-EditorValue push (from Initialize-WebViewForTab's
                # NavigationCompleted handler, e.g. during startup restore or auto-connect) ran
                # while it was still backgrounded and did not reliably show up - force exactly one
                # fresh push now that the tab is genuinely selected/visible. See NeedsEditorSync's
                # definition in New-TabSession.ps1.
                #
                # SuppressEditorSync is set only during a tab's own creation-time selection (New-
                # TabSession), when the editor is not realized yet: pushing then is lost and would
                # consume the flag prematurely, leaving a background restored tab blank until Refresh.
                # The push is deferred to Background priority so it runs after the tab's content has
                # been realized (its WebView2 IsLoaded) - a synchronous push here is skipped as "not
                # loaded" and never reaches the editor.
                if ($TabSession.NeedsEditorSync -and -not $Script:SuppressEditorSync) {
                    $TabSession.NeedsEditorSync = $false
                    $Script:MainForm.Definition.Dispatcher.BeginInvoke(
                        [System.Windows.Threading.DispatcherPriority]::Background,
                        [System.Action] { Set-EditorValue }) | Out-Null
                }

                # The window title mirrors the active tab, and a plain tab switch does not otherwise
                # rebuild this tab's header - refresh the title so it tracks the tab the user moved to.
                Update-ApplicationTitle

                # If the SQL schema window is open, refresh it to the newly-active tab's schema -
                # otherwise it keeps showing the previously-selected tab's database. Get-SqlSchemaObject
                # reuses the per-pool + per-database cache, so a schema that was already retrieved is
                # shown again without another round-trip (mirrors ComboBoxSelectDataConnection).
                if (Test-SqlSchemaFormIsVisible) {
                    Get-SqlSchemaObject
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
