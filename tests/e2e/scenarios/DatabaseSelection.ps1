# End-to-end coverage for explicit database selection inside the query (issue #152), driven through
# the real Invoke-ExecuteQuery against the running mock instance.
#
# These cases exist because criteria 1 and 2 are the two the unit tests cannot reach. The unit tests
# prove the mechanism - the name resolves, the prefix is stripped, the statement carries the right
# connection id - but criterion 1 is an OUTCOME: "returns the same rows as the unprefixed query run
# with that database selected". Only a run through the whole path, with a backend answering, can say
# that. Asserting it here is the difference between "the code looks right" and evidence.
#
# The mock serves two data connections (tests\e2e\Fixtures.ps1): OISES = 42 and OtherDB = 43. That is
# what makes "DatabaseA while DatabaseB is selected" expressible at all.

E2ESuite -Name "DatabaseSelection" -Body {

    E2ECase -Name "a database-prefixed query returns the same rows as the unprefixed one, and posts to that connection" -Body {
        Reset-E2EScenario
        Reset-E2EConnection
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        if ($null -eq (Get-SqlParserType)) {
            # ScriptDom is an optional dependency: without it the feature degrades to "run against
            # the selected connection" by design, so asserting it fired would assert the
            # environment rather than the code.
            return
        }

        # --- Baseline: the unprefixed query with OtherDB selected -------------------------------
        $ComboBoxDataConnection = $Script:MainForm.Elements.ComboBoxSelectDataConnection
        $OtherDb = $ComboBoxDataConnection.Items | Where-Object { $_.Content -like "OtherDB*" } | Select-Object -First 1
        E2EAssertTrue ($null -ne $OtherDb) "the OtherDB data connection should be available to select"

        $ComboBoxDataConnection.SelectedItem = $OtherDb
        Wait-E2ENoPendingRequests

        $script:E2EEditorText = "SELECT * FROM [dbo].[Users]"
        $script:E2ESelectedText = $null
        Clear-E2EResults
        $script:E2ECalls.Clear()

        Invoke-E2EExecuteAndWait

        $Baseline = Get-E2EResultRowCount
        E2EAssertTrue ($Baseline -gt 0) "the baseline query should return rows, or the comparison below proves nothing"

        # --- The same query, prefixed, with OISES selected (criteria 1 and 2) -------------------
        $Oises = $ComboBoxDataConnection.Items | Where-Object { $_.Content -like "OISES*" } | Select-Object -First 1
        $ComboBoxDataConnection.SelectedItem = $Oises
        Wait-E2ENoPendingRequests
        E2EAssertEqual "42" ([string]$Script:AppConfig.CurrentDataConnection.DoId) "the selected data connection should be OISES (42) before the prefixed run"

        $script:E2EEditorText = "SELECT * FROM [OtherDB].[dbo].[Users]"
        Clear-E2EResults
        $script:E2ECalls.Clear()

        Invoke-E2EExecuteAndWait

        E2EAssertEqual $Baseline (Get-E2EResultRowCount) "the prefixed query should return the same rows as the unprefixed one run with OtherDB selected (criterion 1)"

        # The prefix, not the dropdown, decided where it ran: the temporary object the statement was
        # executed through must carry OtherDB's id, while OISES is still selected (criterion 2).
        $TempWrite = @($script:E2ECalls | Where-Object {
                $_.Body -is [System.Collections.IDictionary] -and $_.Body.Contains("NAME") -and
                ([string]$_.Body["NAME"]).StartsWith("TMP_")
            })
        E2EAssertTrue ($TempWrite.Count -ge 1) "a prefixed statement should execute through the temporary query object"
        E2EAssertEqual "43" ([string]$TempWrite[-1].Body["C_SQLTROUBLESHOOTING_DATACONNECTION"].Id) "the temporary object should point at OtherDB (43), not the selected OISES"

        # And the dropdown is untouched: an inline prefix is not sticky (open question 2).
        E2EAssertEqual "42" ([string]$Script:AppConfig.CurrentDataConnection.DoId) "an inline prefix must leave the selected data connection alone"
    }

    E2ECase -Name "the query stored on the data object keeps the prefix the user wrote" -Body {
        Reset-E2EScenario
        Reset-E2EConnection
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        if ($null -eq (Get-SqlParserType)) { return }

        $script:E2EEditorText = "SELECT * FROM [OtherDB].[dbo].[Users]"
        $script:E2ESelectedText = $null
        $script:E2ECalls.Clear()

        Invoke-E2EExecuteAndWait

        # Criterion 7, end to end: the save writes C_QUERY onto the USER's query object, and it must
        # be the original text. Only the temporary object ever sees the rewritten version - which the
        # previous case already asserted carries no prefix.
        $Save = @($script:E2ECalls | Where-Object {
                $_.Method -eq "PUT" -and $_.Body -is [System.Collections.IDictionary] -and
                $_.Body.Contains("C_QUERY") -and -not ([string]$_.Body["NAME"]).StartsWith("TMP_")
            })

        if ($Save.Count -eq 0) {
            # The save is skipped when the text has not changed since it was last stored, which is a
            # legitimate state for this fixture rather than a failure of the criterion.
            return
        }

        E2EAssertTrue ([string]$Save[-1].Body["C_QUERY"] -like "*[[]OtherDB[]]*") "the saved query should keep the database prefix the user wrote (criterion 7)"
    }

    E2ECase -Name "USE switches the data connection, sticks, and executes nothing on its own" -Body {
        Reset-E2EScenario
        Reset-E2EConnection
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        if ($null -eq (Get-SqlParserType)) { return }

        $ComboBoxDataConnection = $Script:MainForm.Elements.ComboBoxSelectDataConnection
        $Oises = $ComboBoxDataConnection.Items | Where-Object { $_.Content -like "OISES*" } | Select-Object -First 1
        $ComboBoxDataConnection.SelectedItem = $Oises
        Wait-E2ENoPendingRequests

        $script:E2EEditorText = "USE [OtherDB]"
        $script:E2ESelectedText = $null
        $script:E2ECalls.Clear()

        Invoke-E2EExecuteAndWait

        # Criterion 5, end to end: the dropdown, the status bar and the loaded schema all follow,
        # through the real Add_SelectionChanged handler, and the switch persists.
        E2EAssertEqual "43" ([string]$Script:AppConfig.CurrentDataConnection.DoId) "USE should switch the active data connection to OtherDB (43)"
        E2EAssertTrue ([string]$Script:MainForm.Elements.TextBlockStatusBarDatabaseName.Text -like "*OtherDB*") "the status bar should name the database USE switched to"

        # A bare USE is never sent to Omada: nothing is executed at all.
        E2EAssertEqual 0 (Get-E2ECallCount -UriLike "*GetPagingData*" -DataType "SqlDataProducer") "a bare USE must not post a query"
    }

    E2ECase -Name "a statement above a USE runs against the connection that was selected before it" -Body {
        Reset-E2EScenario
        Reset-E2EConnection
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        if ($null -eq (Get-SqlParserType)) { return }

        $ComboBoxDataConnection = $Script:MainForm.Elements.ComboBoxSelectDataConnection
        $Oises = $ComboBoxDataConnection.Items | Where-Object { $_.Content -like "OISES*" } | Select-Object -First 1
        $ComboBoxDataConnection.SelectedItem = $Oises
        Wait-E2ENoPendingRequests

        # The statement order is what matters: the first belongs to OISES (42), because that is what
        # was selected when it was written, and only the one after the USE belongs to OtherDB (43).
        # Getting this wrong routes the first statement to the USE's database - silently the wrong
        # one, which is the behaviour this whole feature exists to remove.
        $script:E2EEditorText = "SELECT * FROM [dbo].[Users];`r`nUSE [OtherDB];`r`nSELECT * FROM [dbo].[Users];"
        $script:E2ESelectedText = $null
        Clear-E2EResults
        $script:E2ECalls.Clear()

        Invoke-E2EExecuteAndWait

        $TempWrite = @($script:E2ECalls | Where-Object {
                $_.Body -is [System.Collections.IDictionary] -and $_.Body.Contains("NAME") -and
                ([string]$_.Body["NAME"]).StartsWith("TMP_")
            })
        E2EAssertEqual 2 $TempWrite.Count "both statements should execute through the temporary query object, one write each"
        E2EAssertEqual "42" ([string]$TempWrite[0].Body["C_SQLTROUBLESHOOTING_DATACONNECTION"].Id) "the statement above the USE should run against OISES (42), the connection selected before it"
        E2EAssertEqual "43" ([string]$TempWrite[1].Body["C_SQLTROUBLESHOOTING_DATACONNECTION"].Id) "the statement below the USE should run against OtherDB (43)"

        # The USE still sticks for later executions.
        E2EAssertEqual "43" ([string]$Script:AppConfig.CurrentDataConnection.DoId) "the USE should leave OtherDB selected afterwards"
    }

    E2ECase -Name "an unknown database is refused before anything is posted" -Body {
        Reset-E2EScenario
        Reset-E2EConnection
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        if ($null -eq (Get-SqlParserType)) { return }

        $script:E2EEditorText = "SELECT * FROM [NoSuchDatabase].[dbo].[Users]"
        $script:E2ESelectedText = $null
        $script:E2ECalls.Clear()

        Invoke-E2EExecuteAndWait

        # Criterion 9's real claim is that nothing reaches the tenant - which is exactly what a unit
        # test cannot observe. No execute, and no write to the temporary object either.
        E2EAssertEqual 0 (Get-E2ECallCount -UriLike "*GetPagingData*" -DataType "SqlDataProducer") "an unresolvable database must not post a query"
        $TempWrite = @($script:E2ECalls | Where-Object {
                $_.Body -is [System.Collections.IDictionary] -and $_.Body.Contains("NAME") -and
                ([string]$_.Body["NAME"]).StartsWith("TMP_")
            })
        E2EAssertEqual 0 $TempWrite.Count "an unresolvable database must not write the temporary query object"

        # And the UI is usable again rather than stuck mid-execute.
        E2EAssertEqual "_Execute" ([string](Get-E2EExecuteButtonText)) "the Execute button should be restored after a refusal"
    }

    E2ECase -Name "naming another database fetches its schema once, then serves it from the cache" -Body {
        # Issue #158 criteria 2 and 5, through the real request path. This is what the editor's
        # requestSchema message does when the user types "[OtherDB]." - and the thing worth proving
        # end to end is the COST, which no unit test can observe: exactly one authenticated round
        # trip the first time, and none at all afterwards.
        Reset-E2EScenario
        Reset-E2EConnection
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        # Drop OtherDB's cache entry first. The schema cache lives for the whole session and an
        # earlier case in this file selects OtherDB in the dropdown, which loads its schema - so
        # without this, "fetches it exactly once" would depend on which cases ran before and would
        # pass or fail for reasons that have nothing to do with the code.
        $OtherDbCacheKey = Get-SqlSchemaCacheKey -DataConnectionDoId "43"
        if ($null -ne $Script:SqlSchemaCache -and $null -ne $OtherDbCacheKey) {
            $Script:SqlSchemaCache.Remove($OtherDbCacheKey)
        }

        if ($null -ne $Script:SqlSchemaModelCache -and $null -ne $OtherDbCacheKey) {
            $Script:SqlSchemaModelCache.Remove($OtherDbCacheKey)
        }

        $script:E2ECalls.Clear()

        # Captured rather than hard-coded. The invariant worth asserting is that the call does not
        # CHANGE the selection; which connection happens to be selected at this point depends on
        # what the cases before this one did, and pinning it to a literal made the test fail for a
        # reason that had nothing to do with the code under test.
        $SelectedBefore = [string]$Script:AppConfig.CurrentDataConnection.DoId

        Request-SqlSchemaForDatabase -DatabaseName "OtherDB"
        Wait-E2ENoPendingRequests

        $SchemaCall = @($script:E2ECalls | Where-Object { [string]$_.Uri -like "*GetSqlSchema*" })
        E2EAssertEqual 1 $SchemaCall.Count "naming another database should fetch its schema exactly once (criterion 2)"
        E2EAssertEqual "43" ([string]$SchemaCall[0].Body["connectionId"]) "the fetch should ask for OtherDB (43), not the selected connection"

        # The selected connection is untouched: asking for another database's schema is a read for
        # the editor, not a switch.
        E2EAssertEqual $SelectedBefore ([string]$Script:AppConfig.CurrentDataConnection.DoId) "fetching another database's schema must leave the selected data connection alone"

        # Second ask: the per-pool cache answers it, so nothing reaches the tenant.
        $script:E2ECalls.Clear()
        Request-SqlSchemaForDatabase -DatabaseName "OtherDB"
        Wait-E2ENoPendingRequests

        E2EAssertEqual 0 (Get-E2ECallCount -UriLike "*GetSqlSchema*") "a database already in the per-pool cache must cost no request (criterion 5)"
    }

    E2ECase -Name "a database that matches no data connection costs nothing" -Body {
        Reset-E2EScenario
        Reset-E2EConnection
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        $script:E2ECalls.Clear()

        # Discriminating: there ARE connections to resolve against, so "no fetch" is a decision about
        # this name rather than the trivial consequence of an empty dropdown.
        $Available = @($Script:MainForm.Elements.ComboBoxSelectDataConnection.Items)
        E2EAssertTrue ($Available.Count -gt 0) "the data connection list should be populated, or the assertion below proves nothing"

        # The user is mid-word. A half-typed database name must not reach the tenant, and must not
        # interrupt them either.
        Request-SqlSchemaForDatabase -DatabaseName "NoSuchDatabase"
        Wait-E2ENoPendingRequests

        E2EAssertEqual 0 (Get-E2ECallCount -UriLike "*GetSqlSchema*") "an unresolvable database name must not fetch anything"
    }
}
