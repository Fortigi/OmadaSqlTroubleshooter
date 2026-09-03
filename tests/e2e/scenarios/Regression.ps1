# Validations for the connection-layer bugs fixed this session (in addition to the unit tests under
# tests\*.Tests.ps1, which cover Get-IncrementedQueryName, Test-ShouldConnect, Get-WebViewMessageString,
# Get-DataConnectionOptionList and Set-ShowLogButtonEnabled).

E2ESuite -Name "SchemaCache" -Body {
    E2ECase -Name "the SQL schema is fetched once per pool + data connection and reused from cache" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        # Waited for, so the connect's own schema request has drained before the cache is emptied
        # below. Left outstanding it would suppress BOTH calls, since a request for that key really
        # would already be in flight - and the case would pass for the wrong reason, measuring the
        # in-flight guard instead of the cache.
        Invoke-E2EConnectAndWait

        # Provide the schema window objects Get-SqlSchemaObject writes into (it is normally driven by
        # the schema window). Created on the UI/dispatcher thread so WPF is happy.
        $Script:TreeViewSqlSchema = New-Object System.Windows.Controls.TreeView
        $Script:SqlSchemaForm = [pscustomobject]@{ Definition = (New-Object System.Windows.Window) }

        # Connecting now retrieves the schema itself (the editor's IntelliSense needs it whether or
        # not the schema window is ever opened), so the pool cache is already warm by this point.
        # Empty it so the first call below is a genuine miss and the once-per-pool + per-database
        # contract is what is actually measured.
        $Script:SqlSchemaCache = @{}

        $script:E2ECalls.Clear()
        # Both calls are issued before the first response lands, which is exactly the case the
        # in-flight guard exists for: the cache alone cannot suppress the second one, because the
        # cache is only populated when a response arrives.
        Get-SqlSchemaObject
        Get-SqlSchemaObject
        Wait-E2ENoPendingRequests

        E2EAssertEqual 1 (Get-E2ECallCount -MethodLike "POST" -UriLike "*getsqlschema*") "the schema POST should fire once; the second call is served from the pool cache"
    }

    E2ECase -Name "the setSchema payload carries column names and data types for the editor" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect

        $Script:TreeViewSqlSchema = New-Object System.Windows.Controls.TreeView
        $Script:SqlSchemaForm = [pscustomobject]@{ Definition = (New-Object System.Windows.Window) }

        $script:E2EEditorScripts.Clear()
        Invoke-E2EGetSchemaAndWait

        $SetSchema = $script:E2EEditorScripts | Where-Object { $_ -like "setSchema(*" } | Select-Object -Last 1
        E2EAssertTrue ($null -ne $SetSchema) "a setSchema(...) script should be pushed to the editor"
        # New {n,t} column contract: names under "n", types under "t", with the fixture's types preserved.
        E2EAssertTrue ($SetSchema -match '"n"\s*:') "the setSchema payload should use the 'n' (name) column key"
        E2EAssertTrue ($SetSchema -match '"t"\s*:') "the setSchema payload should use the 't' (type) column key"
        E2EAssertTrue ($SetSchema -like "*nvarchar*") "the setSchema payload should preserve column data types (e.g. nvarchar)"
    }

    E2ECase -Name "the schema still reaches the editor when the SQL schema window was never opened" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect

        # The discriminating part: NO schema window objects at all, exactly as when the user never
        # opens the SQL schema view. Get-SqlSchemaObject used to require these (it wrote the window
        # title and TreeView before pushing), so IntelliSense got no tables/columns until the view
        # was opened. It must now skip the window work and still push to Monaco.
        $Script:TreeViewSqlSchema = $null
        $Script:SqlSchemaForm = $null

        $script:E2EEditorScripts.Clear()
        $script:E2ELogMessages.Clear()
        Invoke-E2EGetSchemaAndWait

        $SetSchema = $script:E2EEditorScripts | Where-Object { $_ -like "setSchema(*" } | Select-Object -Last 1
        E2EAssertTrue ($null -ne $SetSchema) "setSchema(...) must still be pushed with the schema window closed"
        E2EAssertTrue ($SetSchema -like "*Users*") "the payload should still carry the schema's tables"
        E2EAssertTrue ($SetSchema -like "*nvarchar*") "the payload should still carry column data types"

        # And it must do so cleanly - no null-reference error from touching the absent window.
        $Errors = @($script:E2ELogMessages | Where-Object { $_.LogType -eq "ERROR" })
        E2EAssertEqual 0 $Errors.Count ("no errors expected with the schema window closed; got: {0}" -f (($Errors | ForEach-Object { $_.Message }) -join " | "))
    }

    E2ECase -Name "picking a data connection in the ComboBox retrieves the schema without the schema window" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect

        $Script:TreeViewSqlSchema = $null
        $Script:SqlSchemaForm = $null

        # Drive the real ComboBox SelectionChanged handler by selecting the item, the way a user
        # switching database does. That handler is where the Test-SqlSchemaFormIsVisible guard used
        # to sit, so this is the path that has to keep working with the schema view closed.
        $ComboBoxDataConnection = $Script:MainForm.Elements.ComboBoxSelectDataConnection
        $TargetItem = $ComboBoxDataConnection.Items | Where-Object { $_.Content -like "OtherDB*" } | Select-Object -First 1
        E2EAssertTrue ($null -ne $TargetItem) "the OtherDB data connection option should be available to select"

        $script:E2EEditorScripts.Clear()
        $ComboBoxDataConnection.SelectedItem = $TargetItem
        Wait-E2ENoPendingRequests

        $SetSchema = $script:E2EEditorScripts | Where-Object { $_ -like "setSchema(*" } | Select-Object -Last 1
        E2EAssertTrue ($null -ne $SetSchema) "selecting a data connection should push that database's schema to the editor"
        E2EAssertTrue ([string]$Script:AppConfig.CurrentDataConnection.DoId -eq "43") "the handler should have switched the active data connection to OtherDB (43)"
    }
}

E2ESuite -Name "SchemaWindowTabSwitch" -Body {
    E2ECase -Name "switching to another connected tab refreshes the open schema window to that tab's database" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect
        $TabA = Get-ActiveTabSession   # tab A on the default data connection (OISES - 42)

        # Tab B in the same pool but pointed at a DIFFERENT data connection (OtherDB - 43). Set it
        # through the same config path the ComboBox handler uses, so it is deterministic. Both tabs
        # are created BEFORE the window is shown - creating a tab re-activates the main window and
        # would hide an already-shown owned window.
        $TabB = New-E2EConnectedTab
        "OtherDB - 43" | Set-ConfigProperty -Property "CurrentDataConnection"
        E2EAssertTrue ([string]$TabB.AppConfig.CurrentDataConnection.DoId -eq "43") "tab B should be pointed at the OtherDB (43) data connection"

        # Open a real, VISIBLE schema window (tab B is active) so Test-SqlSchemaFormIsVisible is true.
        $Script:SqlSchemaForm = [pscustomobject]@{
            Definition      = (New-Object System.Windows.Window)
            PositionManager = [pscustomobject]@{ Synchronizing = $false }
            State           = "Open"
        }
        $Script:SqlSchemaForm.Definition.Width = 200
        $Script:SqlSchemaForm.Definition.Height = 200
        $Script:SqlSchemaForm.Definition.ShowInTaskbar = $false
        $Script:SqlSchemaForm.Definition.ShowActivated = $false
        # Owner ties it to the (modal ShowDialog) main window so it can actually become visible.
        $Script:SqlSchemaForm.Definition.Owner = $Script:MainForm.Definition
        $Script:TreeViewSqlSchema = New-Object System.Windows.Controls.TreeView
        $Script:SqlSchemaForm.Definition.Content = $Script:TreeViewSqlSchema
        $Script:SqlSchemaForm.Definition.Show()
        # Render-priority flush so IsVisible actually flips before the scenario relies on it.
        $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {}, [System.Windows.Threading.DispatcherPriority]::Render)

        try {
            E2EAssertTrue (Test-SqlSchemaFormIsVisible) "the mock schema window should be visible for the test"
            Invoke-E2EGetSchemaAndWait
            E2EAssertTrue ($Script:SqlSchemaForm.Definition.Title -like "*OtherDB*") "the schema window should first show tab B's database (OtherDB)"

            # Switch to tab A: the schema window must follow it to OISES. This is the discriminating
            # assertion - without the fix the window stays on tab B's OtherDB.
            (Get-TabControlSessions).SelectedItem = $TabA.TabItem
            Wait-E2ENoPendingRequests
            $TitleAfterA = $Script:SqlSchemaForm.Definition.Title
            E2EAssertTrue ($TitleAfterA -like "*OISES*") ("switching to tab A must refresh the schema window to tab A's database (OISES); actual='{0}', visible='{1}'" -f $TitleAfterA, (Test-SqlSchemaFormIsVisible))

            # And switching back to tab B follows it to OtherDB.
            (Get-TabControlSessions).SelectedItem = $TabB.TabItem
            Wait-E2ENoPendingRequests
            E2EAssertTrue ($Script:SqlSchemaForm.Definition.Title -like "*OtherDB*") "switching to tab B must refresh the schema window to tab B's database (OtherDB)"
        }
        finally {
            $Script:SqlSchemaForm.Definition.Close()
            $Script:SqlSchemaForm = $null
            $Script:TreeViewSqlSchema = $null
        }
    }
}

E2ESuite -Name "PoolQuerySharing" -Body {
    E2ECase -Name "connected tabs sharing a pool reuse one session key and see each other's new queries" -Body {
        Reset-E2ETabsToOne

        Set-E2EConnectionFields
        Invoke-E2EConnect
        $TabA = Get-ActiveTabSession

        $TabB = New-E2EConnectedTab
        E2EAssertEqual $TabA.RunTimeData.RestMethodParam.SessionKey $TabB.RunTimeData.RestMethodParam.SessionKey "both tabs should share one connection-pool session key"

        # Save a new query in tab B (the active tab); it must propagate to the connected tab A.
        $TabB.Elements.TextBoxDisplayName.Text = "SharedNewQuery"
        Invoke-E2EClick -ElementName "ButtonNewQuery"

        $InTabA = @($TabA.Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -like "*200" }).Count
        E2EAssertTrue ($InTabA -ge 1) "the new query should appear in the other connected pool tab's dropdown"
    }
}

E2ESuite -Name "TmpQueryInstanceGuid" -Body {
    E2ECase -Name "creating a temporary query reuses the stable InstanceGuid (no regeneration)" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect

        $GuidBefore = $Script:RunTimeConfig.InstanceGuid
        $script:E2ECalls.Clear()

        New-TemporarySqlQueryObject -QueryText "SELECT 1 FROM SomeTable" | Out-Null

        E2EAssertEqual $GuidBefore $Script:RunTimeConfig.InstanceGuid "InstanceGuid must NOT change when a temp query is created (it is shared across tabs / runs)"

        $CreateCall = $script:E2ECalls | Where-Object { $_.Method -eq "POST" -and $_.Uri -like "*odata/dataobjects/C_P_SQLTROUBLESHOOTING" } | Select-Object -First 1
        E2EAssertTrue ($null -ne $CreateCall) "a create POST for the temp query should have been issued"
        E2EAssertEqual ("TMP_{0}" -f $GuidBefore) ([string]$CreateCall.Body["NAME"]) "the temp query name must use the stable TMP_<InstanceGuid>"
    }
}

E2ESuite -Name "BackgroundTabEditor" -Body {
    E2ECase -Name "a background restored tab reloads its query into the editor when first selected" -Body {
        Reset-E2ETabsToOne

        # Two restored + auto-connected tabs, as on startup with 2+ saved sessions. The last one is
        # active; the first is a background tab whose Monaco was never realized.
        $BackgroundTab = New-E2ERestoredTab -DisplayName "Restored1"
        $ActiveTab = New-E2ERestoredTab -DisplayName "Restored2"

        E2EAssertEqual $ActiveTab.Id $Script:ActiveTabId "the last restored tab should be the active tab"
        E2EAssertTrue ($BackgroundTab.NeedsEditorSync) "a background restored tab must still need an editor sync after restore (the flag must NOT be consumed at creation, or its query never re-loads on selection)"

        # Selecting the background tab for the first time must reload its query into the editor.
        $script:E2ECalls.Clear()
        (Get-TabControlSessions).SelectedItem = $BackgroundTab.TabItem
        Invoke-E2EFlushDispatcher

        E2EAssertTrue (-not $BackgroundTab.NeedsEditorSync) "selecting the background tab should consume its NeedsEditorSync flag"
        E2EAssertTrue ((Get-E2ECallCount -MethodLike "GET" -UriLike "*C_P_SQLTROUBLESHOOTING(*") -ge 1) "selecting the background tab should reload its query into the editor (Set-EditorValue -> Get-SqlQueryObject)"
    }
}

E2ESuite -Name "RestoreReconnect" -Body {
    E2ECase -Name "an auto-connected restored tab returns connected with its lists and query selected" -Body {
        Reset-E2ETabsToOne

        $RestoredConfig = [pscustomobject]@{
            Id                    = ([guid]::NewGuid().Guid)
            DisplayName           = "Restored"
            BaseUrl               = "https://tenant.omada.cloud"
            CurrentSqlQuery       = [pscustomobject]@{ DoId = 100; DisplayName = "TestQuery"; FullName = "TestQuery - 100" }
            LastAuthentication    = "Browser"
            UserName              = $null
            Password              = $null
            EntraApplicationIdUri = $null
            EntraIdTenantId       = $null
            MyCreatedQueriesOnly  = $false
            MyUpdatedQueriesOnly  = $false
            SavePassword          = $false
            IdentityUserName      = $null
            CurrentDataConnection = [pscustomobject]@{ DoId = 42; DisplayName = "OISES"; FullName = "OISES - 42" }
        }

        $RestoredTab = New-TabSession -RestoreFrom $RestoredConfig -AutoConnect

        E2EAssertTrue ($RestoredTab.ConnectionStatus) "a restored + auto-connected tab should be Connected (the ReconnectStatus=2 fix)"
        E2EAssertTrue ($RestoredTab.Elements.ComboBoxSelectDataConnection.Items.Count -ge 1) "the restored tab should have its data-connection dropdown populated (auto-connect Update-DataConnectionList)"
        E2EAssertTrue ($null -ne $RestoredTab.Elements.ComboBoxSelectQuery.SelectedItem) "the restored tab should have its saved query selected"
        E2EAssertTrue ([string]$RestoredTab.Elements.ComboBoxSelectQuery.SelectedItem.Content -like "*100") "the selected query should be the restored one"
    }
}
