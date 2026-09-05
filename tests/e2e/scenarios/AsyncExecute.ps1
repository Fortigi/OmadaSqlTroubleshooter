# Issue #40 (Roadmap C1): the query round-trip runs on a background worker and the window stays
# responsive while it does.
#
# These scenarios exercise the REAL machinery. Only the contents of the worker are mocked
# (tests/e2e/OmadaMocks.ps1 shadows Start-OmadaBackgroundRequest to resolve the fixture on the UI
# thread and then wait in a real runspace); the eligibility gate, parameter preparation, the shared
# completion queue, Complete-OmadaBackgroundRequest, the error classification and the 50 ms poll
# timer are all the production code paths.
#
# $script:E2ERequestDelayMs is what makes an execute genuinely slow, so "the window stays responsive
# during a long query" can be observed rather than asserted by assumption.

E2ESuite -Name "AsyncExecute" -Body {

    E2ECase -Name "the execute round-trip does not complete inside the click that started it" -Body {
        # The whole point of the issue, stated as the one assertion that fails against the old
        # synchronous code: after Invoke-E2EExecute returns, the result is NOT yet in hand.
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null
        # This suite runs first, so it is the one scenario that can still race the app's own start-up
        # work: WebView2 posts NavigationCompleted straight to the dispatcher, and the deferred
        # editor/query work it triggers re-enables the very button this case asserts on. Settling
        # first makes the case about the feature rather than about start-up timing.
        Wait-E2EAppSettled

        $script:E2ERequestDelayMs = 700
        $Elements = Get-E2EElements
        $Elements.DataGridQueryResult.ItemsSource = $null

        Invoke-E2EExecute

        E2EAssertTrue ($null -eq $Elements.DataGridQueryResult.ItemsSource) "the grid must not be populated by the time the click returns"
        E2EAssertTrue (Test-E2EExecuteInFlight) "the query should still be outstanding when the click returns"
        E2EAssertEqual "_Cancel" (Get-E2EExecuteButtonText) "the Execute button should read Cancel while the query is in flight"
        E2EAssertTrue $Elements.ButtonExecuteQuery.IsEnabled "the Cancel button must stay enabled - it is the only way out"

        Wait-E2EUntil -TimeoutSeconds 15 -Message "the query to complete" -Condition { -not (Test-E2EExecuteInFlight) }
        Invoke-E2EFlushDispatcher
        E2EAssertEqual 2 (@($Elements.DataGridQueryResult.ItemsSource).Count) "the grid should be populated once the result lands"
    }

    E2ECase -Name "the UI thread stays responsive while a long query is in flight" -Body {
        # "Responsive" measured the only way it can be from inside the app: dispatcher work of a
        # priority BELOW rendering still gets to run promptly while the request is outstanding. Under
        # the old synchronous code the dispatcher was blocked inside Invoke-OmadaRestMethod and this
        # could not have completed at all until the query finished.
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect
        Select-E2EQuery | Out-Null

        $script:E2ERequestDelayMs = 1500
        $Elements = Get-E2EElements

        Invoke-E2EExecute

        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-E2EFlushDispatcher
        $Stopwatch.Stop()

        E2EAssertTrue (Test-E2EExecuteInFlight) "the query should still be in flight for this to mean anything"
        E2EAssertTrue ($Stopwatch.ElapsedMilliseconds -lt 500) ("a dispatcher round-trip took {0} ms while a 1500 ms query was in flight; the UI thread is blocked" -f $Stopwatch.ElapsedMilliseconds)

        Wait-E2ENoPendingRequests
    }

    E2ECase -Name "a tab switch mid-flight works and the result still lands on the originating tab" -Body {
        # The completion queue repoints to the owning tab via Set-ActiveTabContext before invoking a
        # completion block, and restores the previous tab afterwards. With execution off-thread that
        # path is reachable for the first time in a way the user can trigger by hand.
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect
        Select-E2EQuery | Out-Null

        $ExecutingTab = Get-ActiveTabSession
        $ExecutingTab.Elements.DataGridQueryResult.ItemsSource = $null

        $script:E2ERequestDelayMs = 700
        Invoke-E2EExecute

        $OtherTab = New-EmptyTabSession
        E2EAssertTrue ((Get-ActiveTabSession).Id -eq $OtherTab.Id) "the new tab should be active while the first tab's query is in flight"

        Wait-E2EUntil -TimeoutSeconds 15 -Message "the backgrounded tab's query to complete" -Condition {
            -not (Test-E2EExecuteInFlight -TabSession $ExecutingTab)
        }
        Invoke-E2EFlushDispatcher

        E2EAssertEqual 2 (@($ExecutingTab.Elements.DataGridQueryResult.ItemsSource).Count) "the result must land on the tab that issued it"
        E2EAssertTrue ($null -eq $OtherTab.Elements.DataGridQueryResult.ItemsSource) "the result must NOT land on the tab that happened to be active"
        E2EAssertTrue ((Get-ActiveTabSession).Id -eq $OtherTab.Id) "the active tab must be restored after the completion ran"
    }

    E2ECase -Name "two tabs executing at once both get their own result" -Body {
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect
        Select-E2EQuery | Out-Null
        $FirstTab = Get-ActiveTabSession
        $FirstTab.Elements.DataGridQueryResult.ItemsSource = $null

        $script:E2ERequestDelayMs = 900
        Invoke-E2EExecute

        $SecondTab = New-E2EConnectedTab
        Select-E2EQuery | Out-Null
        $SecondTab.Elements.DataGridQueryResult.ItemsSource = $null
        Invoke-E2EExecute

        Wait-E2EUntil -TimeoutSeconds 20 -Message "both tabs' queries to complete" -Condition {
            -not (Test-E2EExecuteInFlight -TabSession $FirstTab) -and -not (Test-E2EExecuteInFlight -TabSession $SecondTab)
        }
        Invoke-E2EFlushDispatcher

        E2EAssertEqual 2 (@($FirstTab.Elements.DataGridQueryResult.ItemsSource).Count) "the first tab should have its own result"
        E2EAssertEqual 2 (@($SecondTab.Elements.DataGridQueryResult.ItemsSource).Count) "the second tab should have its own result"
    }

    E2ECase -Name "an error mid-flight returns the UI to a clean state" -Body {
        # The failure has to arrive from the WORKER, travel back through
        # Complete-OmadaBackgroundRequest and Resolve-OmadaRequestFailure, and still leave the tab
        # usable. Before issue #40 a failing request threw on the UI thread inside the click; now it
        # is a value that crosses a runspace boundary, which is a genuinely different path.
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect
        Select-E2EQuery | Out-Null

        $Elements = Get-E2EElements

        $script:E2ERequestDelayMs = 300
        $script:E2EFixtureOverride = {
            param($Path, $Method, $DataType, $Body)
            if ($DataType -eq "SqlDataProducer") {
                return @{ Value = ([System.Exception]::new("Internal Server Error")) }
            }
            return $null
        }

        try {
            Invoke-E2EExecuteAndWait

            E2EAssertEqual "_Execute" (Get-E2EExecuteButtonText) "the button must be back to Execute after a failure"
            E2EAssertTrue $Elements.ButtonExecuteQuery.IsEnabled "Execute must be re-enabled after a failure"
            E2EAssertTrue $Elements.ButtonSaveQuery.IsEnabled "Save must be re-enabled after a failure"
            E2EAssertTrue (Test-E2EExecutePopupClosed) "no tab may be left showing the 'Executing Query...' popup after a failure"
            # Note, deliberately not asserted as desirable: a failed execute still reports "0 rows"
            # and clears the grid, exactly as it did before this change. That is the "empty result vs
            # failed query" ambiguity of issue #44, and fixing it here would be scope drift. What
            # matters for #40 is that the failure gets back from the worker and the tab is usable.
            E2EAssertTrue ((Get-E2ECallCount -MethodLike "POST" -DataType "SqlDataProducer") -ge 1) "the failing execute should still have been issued"
        }
        finally {
            $script:E2EFixtureOverride = $null
        }
    }

    E2ECase -Name "the elapsed-time indicator counts up while a query is in flight" -Body {
        # Before issue #40 the stopwatch was read exactly once, at the very end - so the number only
        # appeared after the wait was over, which is the one moment it is of no use.
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect
        Select-E2EQuery | Out-Null

        $Elements = Get-E2EElements
        $Elements.TextBlockStatusBarQueryTime.Text = "-"

        $script:E2ERequestDelayMs = 1600
        Invoke-E2EExecute

        Wait-E2EUntil -TimeoutSeconds 10 -Message "the elapsed-time indicator to update mid-flight" -Condition {
            $Elements.TextBlockStatusBarQueryTime.Text -ne "-"
        }
        E2EAssertTrue (Test-E2EExecuteInFlight) "the indicator must have updated while the query was still running"

        Wait-E2ENoPendingRequests
    }

    E2ECase -Name "an unrelated completion landing mid-execute does not re-enable Execute" -Body {
        # Regression guard for a class of bug that only exists now that several requests can be in
        # flight at once: the completion poll timer repoints the tab context around EVERY completion
        # it drains, so a schema fetch landing in the middle of an execute runs Set-ActiveTabContext
        # (and everything downstream of it) while the execute is still outstanding. If any of that
        # re-enables the Execute button, the user can start a second query on a tab that is already
        # running one.
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        $Elements = Get-E2EElements

        $script:E2ERequestDelayMs = 900
        Invoke-E2EExecute
        E2EAssertTrue (Test-E2EExecuteInFlight) "arrange: the query should be in flight"

        # Force a second, unrelated background request onto the queue and let it complete first.
        $Script:SqlSchemaCache = @{}
        $script:E2ERequestDelayMs = 0
        Get-SqlSchemaObject
        Wait-E2EUntil -TimeoutSeconds 10 -Message "the schema request to land" -Condition {
            @($Script:PendingWebViewCompletions | Where-Object { $_.Description -eq "SQL schema" }).Count -eq 0
        }

        E2EAssertEqual "_Cancel" (Get-E2EExecuteButtonText) "the button must still read Cancel: the query it belongs to is still running"

        Wait-E2ENoPendingRequests
        E2EAssertEqual "_Execute" (Get-E2EExecuteButtonText) "the button should be back to Execute once the query itself completes"
    }

    E2ECase -Name "closing a tab abandons its in-flight request instead of letting it repoint the app" -Body {
        # Found while building this suite, and a real defect rather than a tidiness measure. Nothing
        # used to remove a closing tab's entries from the completion queue. A background request's
        # completion calls Set-ActiveTabContext with its own TabSession, which repoints
        # $Script:MainForm.Elements, $Script:RunTimeData, $Script:AppConfig and
        # $Script:ConnectionStatus - onto a tab that no longer exists - and the restore in the poll
        # timer's finally cannot undo it, because Get-ActiveTabSession returns $null when the closed
        # tab was the active one.
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        $KeepTab = Get-ActiveTabSession

        $DoomedTab = New-E2EConnectedTab
        Select-E2EQuery | Out-Null

        $script:E2ERequestDelayMs = 1200
        Invoke-E2EExecute
        E2EAssertEqual 1 (@($Script:PendingWebViewCompletions | Where-Object { $_.Description -eq "Execute query" }).Count) "arrange: the doomed tab should have a query in flight"

        Close-TabSession -TabId $DoomedTab.Id

        E2EAssertEqual 0 (@($Script:PendingWebViewCompletions | Where-Object { $_.Description -eq "Execute query" }).Count) "closing the tab must drop its in-flight request from the completion queue"

        # Pump past the point the abandoned request would have completed, so a completion that
        # somehow survived has every chance to do damage before the assertions below.
        $Deadline = [DateTime]::UtcNow.AddMilliseconds(1800)
        while ([DateTime]::UtcNow -lt $Deadline) {
            Invoke-E2EFlushDispatcher
            Start-Sleep -Milliseconds 50
        }

        E2EAssertTrue ((Get-ActiveTabSession).Id -eq $KeepTab.Id) "the surviving tab must still be the active one"
        E2EAssertTrue ([object]::ReferenceEquals($Script:MainForm.Elements, $KeepTab.Elements)) "the app's element bag must still point at the surviving tab, not the closed one"
    }

    E2ECase -Name "the background path is not taken for a tab that is not connected" -Body {
        # The authentication policy, observed from the outside: off-thread execution is only offered
        # to a session that already authenticated on the UI thread, because OmadaWeb.PS would
        # otherwise open an ownerless login window from a worker.
        Reset-E2ETabsToOne
        Set-E2EConnectionFields
        Invoke-E2EConnect
        Select-E2EQuery | Out-Null

        $Parameters = @{ ForceAuthentication = $false }
        E2EAssertTrue (Test-OmadaBackgroundRequestEligible -Parameters $Parameters) "a connected tab should be eligible"

        $Script:ConnectionStatus = $false
        E2EAssertTrue (-not (Test-OmadaBackgroundRequestEligible -Parameters $Parameters)) "a disconnected tab must not be eligible"

        $Script:ConnectionStatus = $true
        E2EAssertTrue (-not (Test-OmadaBackgroundRequestEligible -Parameters @{ ForceAuthentication = $true })) "a re-authenticating request must not be eligible"
    }
}
