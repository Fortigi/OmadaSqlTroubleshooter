# Tab-management scenarios, including validations for the tab bugs fixed this session.

E2ESuite -Name "TabNavigation" -Body {
    E2ECase -Name "Ctrl+Tab / Ctrl+Shift+Tab cycle through tabs with wraparound" -Body {
        Reset-E2ETabsToOne
        New-EmptyTabSession | Out-Null
        New-EmptyTabSession | Out-Null
        E2EAssertEqual 3 $Script:Tabs.Count "should have exactly 3 tabs for the cycle test"

        (Get-TabControlSessions).SelectedItem = $Script:Tabs[0].TabItem
        E2EAssertEqual 0 (Get-E2EActiveTabIndex) "should start on tab 0"

        Select-AdjacentTab -Direction Next
        E2EAssertEqual 1 (Get-E2EActiveTabIndex) "Next should move to tab 1"
        Select-AdjacentTab -Direction Next
        E2EAssertEqual 2 (Get-E2EActiveTabIndex) "Next should move to tab 2"
        Select-AdjacentTab -Direction Next
        E2EAssertEqual 0 (Get-E2EActiveTabIndex) "Next from the last tab should wrap to tab 0"
        Select-AdjacentTab -Direction Previous
        E2EAssertEqual 2 (Get-E2EActiveTabIndex) "Previous from the first tab should wrap to the last tab"
    }
}

E2ESuite -Name "DuplicateTab" -Body {
    E2ECase -Name "duplicating a tab WITH its query names the copy from the source (increment)" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect
        Select-E2EQuery | Out-Null

        $Source = Get-ActiveTabSession
        E2EAssertEqual "TestQuery" $Source.Elements.TextBoxDisplayName.Text "source display name should be the selected query"

        Complete-DuplicateTab -SourceTabId $Source.Id -SourceConnected $true -EditorText "SELECT 1" -UseSourceName

        $Duplicate = Get-ActiveTabSession
        E2EAssertTrue ($Duplicate.Id -ne $Source.Id) "the duplicate should be a new, active tab"
        E2EAssertEqual "TestQuery1" $Duplicate.Elements.TextBoxDisplayName.Text "duplicate-with-query should be named TestQuery1"
    }

    E2ECase -Name "duplicating a tab WITHOUT its query uses the Query{#} scheme" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect
        Select-E2EQuery | Out-Null

        $Source = Get-ActiveTabSession
        Complete-DuplicateTab -SourceTabId $Source.Id -SourceConnected $true -EditorText "" -UseSourceName:$false

        $Duplicate = Get-ActiveTabSession
        E2EAssertTrue ($Duplicate.Elements.TextBoxDisplayName.Text -like "Query*") "duplicate-without-query should be named Query{#}"
    }
}

E2ESuite -Name "LazyTabLoading" -Body {
    E2ECase -Name "a deferred tab neither connects nor builds its editor until it is first viewed" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect
        $ActiveTab = Get-ActiveTabSession   # fully materialized, connected

        $script:E2ECalls.Clear()
        $Deferred = New-E2EDeferredTab -DisplayName "Lazy"

        # Creating a deferred (restored) tab must not connect or build a WebView2.
        E2EAssertTrue (-not $Deferred.IsMaterialized) "a deferred tab must not be materialized on creation"
        E2EAssertTrue ($null -eq $Deferred.WebView.Object) "a deferred tab must not build its WebView2 on creation"
        E2EAssertEqual 0 (Get-E2ECallCount -MethodLike "GET" -UriLike "*dataobjects/C_P_SQLTROUBLESHOOTING") "a deferred tab must not fire a connect probe until it is viewed"
        E2EAssertTrue ($ActiveTab.IsMaterialized) "the active tab should be materialized"

        # First real selection materializes it: reconnect + editor. Switch away first (the deferred
        # tab is transiently selected at creation), then select it to fire a genuine SelectionChanged.
        (Get-TabControlSessions).SelectedItem = $ActiveTab.TabItem
        $script:E2ECalls.Clear()
        (Get-TabControlSessions).SelectedItem = $Deferred.TabItem
        Invoke-E2EFlushDispatcher

        E2EAssertTrue ($Deferred.IsMaterialized) "selecting a deferred tab for the first time should materialize it"
        E2EAssertTrue ((Get-E2ECallCount -MethodLike "GET" -UriLike "*dataobjects/C_P_SQLTROUBLESHOOTING") -ge 1) "viewing a deferred tab should fire its connect probe"
    }
}

E2ESuite -Name "TabTitleFormat" -Body {
    E2ECase -Name "tab header and window title use the new name/connection/tenant format without DoIds" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect
        $Tab = Get-ActiveTabSession

        # Connected, no query selected yet: "<name> - OISES - tenant.omada.cloud" (no DoId, no state).
        $Header = [string]$Tab.TabItem.Header.Children[0].Text
        E2EAssertTrue ($Header -like "*OISES - tenant.omada.cloud") "a connected tab shows the data connection (no id) and tenant"
        E2EAssertTrue (-not ($Header -like "*No connection*")) "a connected tab does not show a connection-state part"
        E2EAssertTrue (-not ($Header -like "*- 42*")) "the data connection is shown without its DoId"

        # Select a saved query -> its name shows without the trailing DoId.
        Select-E2EQuery | Out-Null
        $Header2 = [string]$Tab.TabItem.Header.Children[0].Text
        E2EAssertTrue ($Header2 -like "TestQuery - *") "the query name is shown without its DoId"
        E2EAssertTrue (-not ($Header2 -like "*100*")) "the query DoId is not shown in the header"

        # The window title mirrors the active tab.
        $Title = [string]$Script:MainForm.Definition.Title
        E2EAssertTrue ($Title -like "*TestQuery - *") "the window title mirrors the active tab's query name"

        # Unsaved changes -> a '*' marker on the query name, in both header and title.
        $Tab.IsDirty = $true
        Update-TabHeaderTitle -TabSession $Tab
        E2EAssertTrue (([string]$Tab.TabItem.Header.Children[0].Text).Contains("TestQuery*")) "an unsaved tab shows the * marker in the header"
        E2EAssertTrue (([string]$Script:MainForm.Definition.Title).Contains("TestQuery*")) "an unsaved tab shows the * marker in the window title"
        $Tab.IsDirty = $false

        # Disconnect -> 'No connection' is appended (only when there is no connection).
        Invoke-E2EConnect
        E2EAssertTrue (([string]$Tab.TabItem.Header.Children[0].Text) -like "*No connection") "a disconnected tab ends with 'No connection'"
        E2EAssertTrue (([string]$Script:MainForm.Definition.Title) -like "*No connection") "the window title shows 'No connection' when the active tab is disconnected"
    }

    E2ECase -Name "the window title actively follows the active tab when switching tabs" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect
        Select-E2EQuery | Out-Null
        $TabA = Get-ActiveTabSession   # query TestQuery selected

        $TabB = New-E2EConnectedTab    # no query selected; becomes active
        E2EAssertTrue (-not (([string]$Script:MainForm.Definition.Title) -like "*TestQuery*")) "after moving to tab B the title no longer shows tab A's query"

        (Get-TabControlSessions).SelectedItem = $TabA.TabItem
        E2EAssertTrue (([string]$Script:MainForm.Definition.Title) -like "*TestQuery*") "switching back to tab A updates the window title to tab A's query"
    }
}

E2ESuite -Name "DisconnectContext" -Body {
    E2ECase -Name "clicking a tab's Disconnect acts on that tab even if the active context points elsewhere" -Body {
        Reset-E2ETabsToOne

        Set-E2EConnectionFields
        Invoke-E2EConnect
        $TabA = Get-ActiveTabSession

        $TabB = New-E2EConnectedTab   # TabB is now the active/last tab

        # Simulate the bug's precondition: TabA is the visible (selected) tab, but the global active
        # context has leaked to a background tab (TabB) - as an unrestored NavigationCompleted would.
        (Get-TabControlSessions).SelectedItem = $TabA.TabItem
        Set-ActiveTabContext -TabSession $TabB

        E2EAssertTrue ($TabA.ConnectionStatus) "TabA should be connected before the disconnect"
        E2EAssertTrue ($TabB.ConnectionStatus) "TabB should be connected before the disconnect"

        # Click TabA's OWN Disconnect button.
        $TabA.Elements.ButtonConnect.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))

        E2EAssertTrue (-not $TabA.ConnectionStatus) "clicking TabA's Disconnect must disconnect TabA (not the mis-pointed context tab)"
        E2EAssertTrue ($TabB.ConnectionStatus) "TabB must stay connected"
    }
}

E2ESuite -Name "TabRename" -Body {
    E2ECase -Name "renaming a tab records a DEBUG trace of the old and new name" -Body {
        Reset-E2ETabsToOne
        $Tab = Get-ActiveTabSession

        # Make the Display name field drive the tab name (no query selected -> Get-TabName rule 2),
        # then establish a starting name.
        $Tab.Elements.ComboBoxSelectQuery.SelectedItem = $null
        $Tab.Elements.ComboBoxSelectQuery.Text = ""
        $Tab.Elements.TextBoxDisplayName.Text = "RenameStart"

        Clear-E2ELog
        $Tab.Elements.TextBoxDisplayName.Text = "RenameEnd"

        $Renamed = Get-E2ELogMessages -LogType DEBUG -MessageLike "*Tab renamed from 'RenameStart' to 'RenameEnd'*"
        E2EAssertTrue ($Renamed.Count -ge 1) "renaming a tab should log a 'Tab renamed from ... to ...' DEBUG trace"
    }
}

E2ESuite -Name "CloseTab" -Body {
    E2ECase -Name "closing the active tab selects the previous (left) tab" -Body {
        Reset-E2ETabsToOne
        $TabA = Get-ActiveTabSession
        New-EmptyTabSession | Out-Null
        $TabB = Get-ActiveTabSession
        New-EmptyTabSession | Out-Null
        $TabC = Get-ActiveTabSession

        # tabs [A, B, C], C active -> closing C returns to B (the previous tab).
        Close-TabSession -TabId $TabC.Id
        E2EAssertEqual $TabB.Id (Get-ActiveTabSession).Id "closing the active last tab should select the previous tab"

        # [A, B], B active -> closing B returns to A.
        Close-TabSession -TabId $TabB.Id
        E2EAssertEqual $TabA.Id (Get-ActiveTabSession).Id "closing again should select the previous tab"
    }

    E2ECase -Name "closing a middle active tab selects the previous (left) tab, not the next" -Body {
        Reset-E2ETabsToOne
        $TabA = Get-ActiveTabSession
        New-EmptyTabSession | Out-Null
        New-EmptyTabSession | Out-Null
        $TabB = $Script:Tabs[1]
        (Get-TabControlSessions).SelectedItem = $TabB.TabItem   # activate the MIDDLE tab

        Close-TabSession -TabId $TabB.Id
        E2EAssertEqual $TabA.Id (Get-ActiveTabSession).Id "closing a middle tab should select the previous (left) tab, not the next"
    }

    E2ECase -Name "closing a never-viewed lazy tab does not error" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect
        $Active = Get-ActiveTabSession
        $Deferred = New-E2EDeferredTab -DisplayName "LazyClose"   # becomes active, no WebView2
        E2EAssertTrue ($null -eq $Deferred.WebView.Object) "the deferred tab has no WebView2 to dispose"

        $BeforeCount = $Script:Tabs.Count
        Close-TabSession -TabId $Deferred.Id
        E2EAssertEqual ($BeforeCount - 1) $Script:Tabs.Count "closing a lazy tab removes it without error"
        E2EAssertEqual $Active.Id (Get-ActiveTabSession).Id "closing the lazy tab returns to the previous tab"
    }

    E2ECase -Name "closing the active tab selects a surviving tab" -Body {
        Reset-E2ETabsToOne
        New-EmptyTabSession | Out-Null
        $BeforeCount = $Script:Tabs.Count
        $Active = Get-ActiveTabSession

        Close-TabSession -TabId $Active.Id

        E2EAssertEqual ($BeforeCount - 1) $Script:Tabs.Count "closing a tab should reduce the tab count by one"
        E2EAssertTrue ($null -ne (Get-ActiveTabSession)) "a surviving tab should be active after a close"
    }

    E2ECase -Name "choosing Save on a dirty tab that cannot save aborts the close (no data loss)" -Body {
        Reset-E2ETabsToOne
        New-EmptyTabSession | Out-Null
        $DirtyTab = Get-ActiveTabSession
        $DirtyTab.IsDirty = $true
        $BeforeCount = $Script:Tabs.Count

        # The mocked editor never enqueues a real save Task (no rendered WebView2), so choosing "Save"
        # must NOT close the tab and lose the unsaved changes.
        $script:E2EChoiceReturn = 1   # "Save"
        Close-TabSession -TabId $DirtyTab.Id

        E2EAssertEqual $BeforeCount $Script:Tabs.Count "a dirty tab must NOT be closed when Save is chosen but no save task can be created"

        $DirtyTab.IsDirty = $false   # clean up so later resets can collapse tabs
    }

    E2ECase -Name "Close All leaves no session tabs and does not crash" -Body {
        Reset-E2ETabsToOne
        New-EmptyTabSession | Out-Null
        Close-AllTabSessions
        E2EAssertEqual 0 $Script:Tabs.Count "Close All should leave zero session tabs"
    }
}
