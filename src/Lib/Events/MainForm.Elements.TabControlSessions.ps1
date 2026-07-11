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

                # This tab's first Set-EditorValue push (from Initialize-WebViewForTab's
                # NavigationCompleted handler, e.g. during startup restore or auto-connect) ran
                # while it was still backgrounded and did not reliably show up - force exactly one
                # fresh push now that the tab is genuinely selected/visible. See NeedsEditorSync's
                # definition in New-TabSession.ps1.
                if ($TabSession.NeedsEditorSync) {
                    $TabSession.NeedsEditorSync = $false
                    Set-EditorValue
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
