# Issue #40 (Roadmap C1): the Cancel button.
#
# Cancel here means "stop waiting", not "stop the query" - Omada goes on executing it, and there is
# no server-side cancellation to call (issue #43). These scenarios hold the app to exactly that: the
# tab comes back to a usable state, the temporary object created for an execute-selection run is
# still cleaned up, and nothing claims more than the app can actually do.

E2ESuite -Name "CancelExecute" -Body {

    E2ECase -Name "the Execute button becomes Cancel while a query is in flight, and back again" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        E2EAssertEqual "_Execute" (Get-E2EExecuteButtonText) "arrange: the button should read Execute before anything runs"

        $script:E2ERequestDelayMs = 900
        Invoke-E2EExecute

        E2EAssertEqual "_Cancel" (Get-E2EExecuteButtonText) "the button must read Cancel while the query is in flight"

        Wait-E2EUntil -TimeoutSeconds 15 -Message "the query to finish" -Condition { -not (Test-E2EExecuteInFlight) }
        Invoke-E2EFlushDispatcher
        E2EAssertEqual "_Execute" (Get-E2EExecuteButtonText) "the button must return to Execute once the query completes"
    }

    E2ECase -Name "cancelling mid-flight returns the tab to a usable state" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        $Elements = Get-E2EElements
        $script:E2ERequestDelayMs = 4000
        Invoke-E2EExecute
        E2EAssertTrue (Test-E2EExecuteInFlight) "arrange: the query should be in flight"

        # The second click is the Cancel: same button, different meaning.
        Invoke-E2EExecute

        E2EAssertTrue (-not (Test-E2EExecuteInFlight)) "cancelling must take the request off the completion queue immediately"
        E2EAssertEqual "_Execute" (Get-E2EExecuteButtonText) "the button must go back to Execute in the same click"
        E2EAssertTrue $Elements.ButtonExecuteQuery.IsEnabled "Execute must be usable again"
        E2EAssertTrue $Elements.ButtonSaveQuery.IsEnabled "Save must be usable again"
        E2EAssertTrue (Test-E2EExecutePopupClosed) "no tab may be left showing the 'Executing Query...' popup"
    }

    E2ECase -Name "cancelling does not blank a previous result" -Body {
        # Abandoning a query is not a reason to throw away what the user was already looking at.
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        Invoke-E2EExecuteAndWait
        $Elements = Get-E2EElements
        E2EAssertEqual 2 (@($Elements.DataGridQueryResult.ItemsSource).Count) "arrange: the grid should hold a result"

        $script:E2ERequestDelayMs = 4000
        Invoke-E2EExecute
        Invoke-E2EExecute   # cancel

        E2EAssertEqual 2 (@($Elements.DataGridQueryResult.ItemsSource).Count) "the previous result must survive a cancellation"
    }

    E2ECase -Name "cancelling says so honestly, without claiming the query was stopped" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        Clear-E2ELog
        $script:E2ERequestDelayMs = 4000
        Invoke-E2EExecute
        Invoke-E2EExecute   # cancel

        $Messages = @(Get-E2ELogMessages | ForEach-Object { $_.Message })
        E2EAssertTrue (@($Messages | Where-Object { $_ -like "*may still be running on the server*" }).Count -ge 1) "the user must be told the query keeps running server-side"
        E2EAssertTrue (@($Messages | Where-Object { $_ -like "*cancelled the query*" -or $_ -like "*query was stopped*" }).Count -eq 0) "nothing may claim the query itself was stopped - the app cannot do that (issue #43)"
    }

    E2ECase -Name "cancelling an execute-selection run still deletes the temporary query object" -Body {
        # The leak this case exists for: the temporary TMP_<guid> object is created before the
        # request and deleted by the completion, so cancelling in between would leave it on the
        # tenant. New-TemporarySqlQueryObject reuses a stale one on the next run so the damage
        # self-heals, but leaving litter because someone clicked Cancel is not acceptable.
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        # A selection makes Invoke-ExecuteQuery create a temporary object to execute against.
        $script:E2ESelectedText = "SELECT TOP 1 * FROM dbo.Users"
        $script:E2ERequestDelayMs = 4000
        $script:E2ECalls.Clear()

        Invoke-E2EExecute
        E2EAssertTrue ((Get-E2ECallCount -MethodLike "POST" -UriLike "*C_P_SQLTROUBLESHOOTING") -ge 1) "arrange: a temporary query object should have been created"

        Invoke-E2EExecute   # cancel

        E2EAssertTrue ((Get-E2ECallCount -MethodLike "DELETE") -ge 1) "cancelling must delete the temporary query object it left on the tenant"

        $script:E2ESelectedText = $null
    }

    E2ECase -Name "a cancelled query's late response never reaches the grid" -Body {
        # The worker may take a moment to stop, and its result must not arrive afterwards and
        # overwrite what the user is looking at now.
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        Invoke-E2EExecuteAndWait
        $Elements = Get-E2EElements
        $BeforeCount = @($Elements.DataGridQueryResult.ItemsSource).Count

        $script:E2ERequestDelayMs = 800
        Invoke-E2EExecute
        Invoke-E2EExecute   # cancel

        # Pump well past the point the abandoned worker would have finished.
        $Deadline = [DateTime]::UtcNow.AddMilliseconds(1600)
        while ([DateTime]::UtcNow -lt $Deadline) {
            Invoke-E2EFlushDispatcher
            Start-Sleep -Milliseconds 50
        }

        E2EAssertEqual $BeforeCount (@($Elements.DataGridQueryResult.ItemsSource).Count) "a cancelled query's late result must not land in the grid"
        E2EAssertEqual "_Execute" (Get-E2EExecuteButtonText) "the tab must still be in the Execute state"
    }

    E2ECase -Name "cancelling one tab leaves another tab's query running" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null
        $FirstTab = Get-ActiveTabSession

        $script:E2ERequestDelayMs = 2500
        Invoke-E2EExecute

        # Built by hand rather than with New-E2EConnectedTab, which drains every pending request -
        # including the first tab's query, which is the very thing this case needs still running.
        New-EmptyTabSession | Out-Null
        $SecondTab = Get-ActiveTabSession
        Set-E2EConnectionFields
        Invoke-E2EConnect
        Select-E2EQuery | Out-Null
        Invoke-E2EExecute
        E2EAssertTrue (Test-E2EExecuteInFlight -TabSession $FirstTab) "arrange: the first tab should still be executing"
        E2EAssertTrue (Test-E2EExecuteInFlight -TabSession $SecondTab) "arrange: the second tab should be executing too"

        Invoke-E2EExecute   # cancel, on the second tab

        E2EAssertTrue (-not (Test-E2EExecuteInFlight -TabSession $SecondTab)) "the second tab's query must be cancelled"
        E2EAssertTrue (Test-E2EExecuteInFlight -TabSession $FirstTab) "the first tab's query must be untouched"

        Wait-E2ENoPendingRequests -TimeoutSeconds 20
    }
}
