# Validations for the connection-layer bugs fixed this session (in addition to the unit tests under
# tests\*.Tests.ps1, which cover Get-IncrementedQueryName, Test-ShouldConnect, Get-WebViewMessageString,
# Get-DataConnectionOptionList and Set-ShowLogButtonEnabled).

E2ESuite -Name "SchemaCache" -Body {
    E2ECase -Name "the SQL schema is fetched once per pool + data connection and reused from cache" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect

        # Provide the schema window objects Get-SqlSchemaObject writes into (it is normally driven by
        # the schema window). Created on the UI/dispatcher thread so WPF is happy.
        $Script:TreeViewSqlSchema = New-Object System.Windows.Controls.TreeView
        $Script:SqlSchemaForm = [pscustomobject]@{ Definition = (New-Object System.Windows.Window) }

        $script:E2ECalls.Clear()
        Get-SqlSchemaObject
        Get-SqlSchemaObject

        E2EAssertEqual 1 (Get-E2ECallCount -MethodLike "POST" -UriLike "*getsqlschema*") "the schema POST should fire once; the second call is served from the pool cache"
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
