# Core happy-path + error scenarios. Proves connect -> list -> select -> execute -> results end to
# end against the mocked backend, driving the REAL buttons/handlers.

E2ESuite -Name "Connect" -Body {
    E2ECase -Name "connecting populates connection state and the query + data-connection lists" -Body {
        Reset-E2EScenario
        Reset-E2EConnection

        Set-E2EConnectionFields
        Invoke-E2EConnect

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
        Invoke-E2EConnect

        $Item = Select-E2EQuery
        E2EAssertTrue ($null -ne $Item) "Query item 'TestQuery - 100' should exist in the dropdown"

        Invoke-E2EExecute

        $Elements = Get-E2EElements
        E2EAssertEqual 2 ([int]$Script:RunTimeData.QueryResult.d.Records) "Records count should match the fixture"
        E2EAssertEqual 2 (@($Elements.DataGridQueryResult.ItemsSource).Count) "DataGrid should show the fixture rows"
        E2EAssertTrue ((Get-E2ECallCount -MethodLike "POST" -DataType "SqlDataProducer") -eq 1) "Exactly one SqlDataProducer execute should have fired"
    }

    E2ECase -Name "a query returning no rows clears the grid without error" -Body {
        Reset-E2EScenario
        Reset-E2EConnection
        $script:E2EResultRows = @()
        Set-E2EConnectionFields
        Invoke-E2EConnect
        Select-E2EQuery | Out-Null
        Invoke-E2EExecute

        $Elements = Get-E2EElements
        E2EAssertEqual 0 ([int]$Script:RunTimeData.QueryResult.d.Records) "Records should be 0 for an empty result"
        E2EAssertTrue ($null -eq $Elements.DataGridQueryResult.ItemsSource) "ItemsSource should be null for an empty result"
    }
}

E2ESuite -Name "SaveAsNew" -Body {
    E2ECase -Name "saving a query as new posts it and adds it to the dropdown" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect

        $Elements = Get-E2EElements
        $Elements.TextBoxDisplayName.Text = "MyBrandNewQuery"
        Invoke-E2EClick -ElementName "ButtonNewQuery"

        E2EAssertTrue ((Get-E2ECallCount -MethodLike "POST" -UriLike "*odata/dataobjects/C_P_SQLTROUBLESHOOTING") -ge 1) "a create POST should have been issued"
        E2EAssertTrue (@($Elements.ComboBoxSelectQuery.Items | Where-Object { $_.Content -like "*200" }).Count -ge 1) "the new query should appear in the dropdown"
    }

    E2ECase -Name "an empty display name is rejected (no create POST)" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect

        $Elements = Get-E2EElements
        $Elements.TextBoxDisplayName.Text = ""
        $script:E2ECalls.Clear()
        Invoke-E2EClick -ElementName "ButtonNewQuery"

        E2EAssertEqual 0 (Get-E2ECallCount -MethodLike "POST" -UriLike "*odata/dataobjects/C_P_SQLTROUBLESHOOTING") "an empty display name should not create a query"
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
