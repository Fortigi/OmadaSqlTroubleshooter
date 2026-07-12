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

E2ESuite -Name "CloseTab" -Body {
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
