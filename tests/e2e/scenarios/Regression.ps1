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
