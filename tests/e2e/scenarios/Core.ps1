# Core happy-path + error scenarios. Proves connect -> list -> select -> execute -> results end to
# end against the mocked backend, driving the REAL buttons/handlers.

E2ESuite -Name "Connect" -Body {
    E2ECase -Name "connecting populates connection state and the query + data-connection lists" -Body {
        Reset-E2EScenario
        Reset-E2EConnection

        Set-E2EConnectionFields
        # AndWait since issue #90: the data connection list is fetched on a background worker now, so
        # the dropdown this case asserts on is populated by a completion rather than before the click
        # returns. The same reason Invoke-E2EConnectAndWait was added for the schema fetch in #40.
        Invoke-E2EConnectAndWait

        $Elements = Get-E2EElements
        E2EAssertTrue $Script:ConnectionStatus "ConnectionStatus should be true after a successful connect"
        E2EAssertTrue ($Elements.ComboBoxSelectQuery.Items.Count -ge 1) "Query dropdown should be populated"
        E2EAssertTrue ($Elements.ComboBoxSelectDataConnection.Items.Count -ge 1) "Data connection dropdown should be populated"
        E2EAssertTrue ((Get-E2ECallCount -MethodLike "GET" -UriLike "*C_P_SQLTROUBLESHOOTING*") -ge 1) "A connection probe GET should have been issued"
    }
}

E2ESuite -Name "Execute" -Body {
    E2ECase -Name "executing a selected query populates the results grid" -Body {
        Reset-E2EScenario
        Reset-E2EConnection
        Set-E2EConnectionFields
        # AndWait since issue #90: connect's list fetches land on completions now, and one arriving
        # mid-execute is exactly what "exactly one execute should have fired" is there to catch.
        Invoke-E2EConnectAndWait

        $Item = Select-E2EQuery
        E2EAssertTrue ($null -ne $Item) "Query item 'TestQuery - 100' should exist in the dropdown"

        Invoke-E2EExecuteAndWait

        $Elements = Get-E2EElements
        E2EAssertEqual 2 ([int]$Script:RunTimeData.QueryResult.d.Records) "Records count should match the fixture"
        E2EAssertEqual 2 (Get-E2EResultRowCount) "The first result should show the fixture rows"
        E2EAssertTrue ((Get-E2ECallCount -MethodLike "POST" -DataType "SqlDataProducer") -eq 1) "Exactly one SqlDataProducer execute should have fired"
    }

    E2ECase -Name "a query returning no rows clears the grid without error" -Body {
        Reset-E2EScenario
        Reset-E2EConnection
        $script:E2EResultRows = @()
        Set-E2EConnectionFields
        Invoke-E2EConnect
        Select-E2EQuery | Out-Null
        Invoke-E2EExecuteAndWait

        $Elements = Get-E2EElements
        E2EAssertEqual 0 ([int]$Script:RunTimeData.QueryResult.d.Records) "Records should be 0 for an empty result"
        E2EAssertEqual 0 (Get-E2EResultCount) "No result should be bound for an empty result"
    }
}

E2ESuite -Name "SaveAsNew" -Body {
    E2ECase -Name "saving an ad-hoc query asks a name, posts it and adds it to the dropdown" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect

        # No query selected: the editor is an ad-hoc query. Save asks for a name in a pop-up.
        $script:E2EEditorText = "SELECT 1"
        (Get-ActiveTabSession).EditorText = "SELECT 1"
        $script:E2EInputText = "MyBrandNewQuery"
        try {
            $Elements = Get-E2EElements
            Invoke-E2EClick -ElementName "ButtonSaveQuery"
        }
        finally {
            $script:E2EInputText = $null
        }

        E2EAssertTrue ((Get-E2ECallCount -MethodLike "POST" -UriLike "*odata/dataobjects/C_P_SQLTROUBLESHOOTING") -ge 1) "a create POST should have been issued"
        E2EAssertTrue (@($Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -like "*200" }).Count -ge 1) "the new query should appear in the dropdown"
    }

    E2ECase -Name "an empty editor is not offered to be saved (no create POST)" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect

        $script:E2EEditorText = ""
        (Get-ActiveTabSession).EditorText = ""
        $script:E2ECalls.Clear()
        try {
            Invoke-E2EClick -ElementName "ButtonSaveQuery"
        }
        finally {
            $script:E2EEditorText = "SELECT 1"
        }

        E2EAssertEqual 0 (Get-E2ECallCount -MethodLike "POST" -UriLike "*odata/dataobjects/C_P_SQLTROUBLESHOOTING") "an empty editor should not create a query"
    }

    E2ECase -Name "New clears the selected query and leaves New enabled" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect
        Select-E2EQuery | Out-Null
        $script:E2ECalls.Clear()

        Invoke-E2EClick -ElementName "ButtonNewQuery"

        $Elements = Get-E2EElements
        E2EAssertTrue ($null -eq $Elements.ComboBoxSelectQuery.SelectedItem) "New should clear the query selection"
        E2EAssertTrue ([string]::IsNullOrWhiteSpace([string]$Script:AppConfig.CurrentSqlQuery.DoId)) "New should leave an ad-hoc query"
        E2EAssertTrue ([bool]$Elements.ButtonNewQuery.IsEnabled) "New must not be left disabled"
        E2EAssertEqual 0 (Get-E2ECallCount -MethodLike "POST" -UriLike "*odata/dataobjects/C_P_SQLTROUBLESHOOTING") "New must not create anything on the tenant"
    }
}

E2ESuite -Name "ConnectFailure" -Body {
    E2ECase -Name "a 401 on the connection probe leaves the app disconnected without crashing" -Body {
        Reset-E2EScenario
        Reset-E2EConnection
        $script:E2EConnectionProbeError = [System.Exception]::new("Unauthorized (401) - simulated by E2E")
        Set-E2EConnectionFields
        Invoke-E2EConnect

        E2EAssertTrue (-not $Script:ConnectionStatus) "ConnectionStatus should be false after a failed connect"
    }
}
