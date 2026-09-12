# End-to-end coverage for the three client-side validation passes of issue #61, driven through the
# real Invoke-ExecuteQuery against the running mock instance.
#
# What only an E2E run can prove is the part the unit tests cannot even see: that the whole gate -
# read the editor, check the text, push the markers, ask, obey the answer - costs the tenant NOTHING.
# The unit tests assert the passes make no request of their own; these cases assert that no request
# reached the mock server, which is the claim acceptance criterion 5 actually makes.
#
# Every case runs against the same schema the editor's IntelliSense was given, because that is the
# schema the pass resolves against: dbo.Users and its columns come from the mock fixture
# (tests\e2e\Fixtures.ps1), not from anything this file declares.

E2ESuite -Name "Validation" -Body {

    E2ECase -Name "a syntax error is marked in the editor and asked about, and declining costs no round trip" -Body {
        Reset-E2EScenario
        Reset-E2EConnection
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        if (-not (Get-SqlValidationSetting).Enabled) {
            # ScriptDom is an optional dependency (acceptance criterion 6). On an agent where it could
            # not be installed the feature is off, and asserting it fired would be asserting the
            # environment rather than the code.
            return
        }

        $script:E2EEditorText = "SELECT a, FROM dbo.Users"
        $script:E2ESelectedText = $null
        $script:E2EChoiceReturn = $false

        Clear-E2EChoices
        $script:E2EEditorScripts.Clear()
        $script:E2ECalls.Clear()

        Invoke-E2EExecuteAndWait

        $Diagnostics = $script:E2EEditorScripts | Where-Object { $_ -like "setDiagnostics(*" } | Select-Object -Last 1
        E2EAssertTrue ($null -ne $Diagnostics) "a setDiagnostics(...) script should be pushed to the editor"
        E2EAssertTrue ($Diagnostics -like '*T-SQL syntax*') "the marker should name the syntax pass as its source"

        E2EAssertEqual 1 (Get-E2EChoices -TitleLike "Check the query").Count "executing with a syntax error should ask once"
        E2EAssertEqual 0 (Get-E2ECallCount -UriLike "*sqldataproducer*") "declining must not spend a round trip on the query"

        $script:E2EChoiceReturn = $null
        $script:E2EEditorText = "SELECT 1 AS a"
    }

    E2ECase -Name "an unnamed result column raises the Omada compatibility rule before execution" -Body {
        # The rule that pays for the whole third pass: this query runs, and the result arrives empty
        # with "Query did not return any results!" - which is the worst failure mode in this tool.
        Reset-E2EScenario
        Reset-E2EConnection
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        if (-not (Get-SqlValidationSetting).OmadaEnabled) {
            return
        }

        $script:E2EEditorText = "SELECT Id, COUNT(*) FROM dbo.Users GROUP BY Id"
        $script:E2ESelectedText = $null
        $script:E2EChoiceReturn = $false

        Clear-E2EChoices
        $script:E2EEditorScripts.Clear()
        $script:E2ECalls.Clear()

        Invoke-E2EExecuteAndWait

        $Diagnostics = $script:E2EEditorScripts | Where-Object { $_ -like "setDiagnostics(*" } | Select-Object -Last 1
        E2EAssertTrue ($null -ne $Diagnostics) "a setDiagnostics(...) script should be pushed to the editor"
        E2EAssertTrue ($Diagnostics -like '*Omada compatibility*') "the marker should name the compatibility pass as its source"
        E2EAssertTrue ($Diagnostics -like '*Omada returns no rows*') "the message must name the symptom the user already knows"

        E2EAssertEqual 1 (Get-E2EChoices -TitleLike "Check the query").Count "an unnamed result column should ask once before execution"
        E2EAssertEqual 0 (Get-E2ECallCount -UriLike "*sqldataproducer*") "the warning arrives before any round trip is spent"

        $script:E2EChoiceReturn = $null
        $script:E2EEditorText = "SELECT 1 AS a"
    }

    E2ECase -Name "a schema warning is marked but never gates execution" -Body {
        # Acceptance criterion 4. The column does not exist in the cached schema, so the pass warns -
        # and the query runs anyway, without a question, because the cache can be stale and the
        # schema's coverage of views and functions is not guaranteed.
        Reset-E2EScenario
        Reset-E2EConnection
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        if (-not (Get-SqlValidationSetting).SchemaEnabled) {
            return
        }

        $script:E2EEditorText = "SELECT u.NoSuchColumn AS n FROM dbo.Users u"
        $script:E2ESelectedText = $null

        Clear-E2EChoices
        $script:E2EEditorScripts.Clear()
        $script:E2ECalls.Clear()

        Invoke-E2EExecuteAndWait

        $Diagnostics = $script:E2EEditorScripts | Where-Object { $_ -like "setDiagnostics(*" } | Select-Object -Last 1
        E2EAssertTrue ($null -ne $Diagnostics) "a setDiagnostics(...) script should be pushed to the editor"
        E2EAssertTrue ($Diagnostics -like '*SQL schema*') "the marker should name the schema pass as its source"
        E2EAssertTrue ($Diagnostics -like '*not found in the cached schema*') "the wording must not claim the column does not exist"

        E2EAssertEqual 0 (Get-E2EChoices -TitleLike "Check the query").Count "a schema warning must never ask before executing"

        $script:E2EEditorText = "SELECT 1 AS a"
    }

    E2ECase -Name "a clean query is marked clean and asks nothing" -Body {
        Reset-E2EScenario
        Reset-E2EConnection
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        if (-not (Get-SqlValidationSetting).Enabled) {
            return
        }

        $script:E2EEditorText = "SELECT u.Id, u.Name FROM dbo.Users u"
        $script:E2ESelectedText = $null

        Clear-E2EChoices
        $script:E2EEditorScripts.Clear()

        Invoke-E2EExecuteAndWait

        $Diagnostics = $script:E2EEditorScripts | Where-Object { $_ -like "setDiagnostics(*" } | Select-Object -Last 1
        E2EAssertEqual "setDiagnostics([]);" $Diagnostics "a clean query clears the markers rather than leaving stale ones"
        E2EAssertEqual 0 (Get-E2EChoices -TitleLike "Check the query").Count "a clean query asks nothing"

        $script:E2EEditorText = "SELECT 1 AS a"
    }

    E2ECase -Name "refreshing the schema drops both caches and fetches again" -Body {
        # The "Refresh schema" action of issue #61 section 2. A stale cache is why the schema pass only
        # ever warns; this is the user's way of saying "it changed, look again".
        Reset-E2EScenario
        Reset-E2EConnection
        Set-E2EConnectionFields
        Invoke-E2EConnectAndWait
        Select-E2EQuery | Out-Null

        $Script:TreeViewSqlSchema = New-Object System.Windows.Controls.TreeView
        $Script:SqlSchemaForm = [pscustomobject]@{ Definition = (New-Object System.Windows.Window) }

        Invoke-E2EGetSchemaAndWait
        $CacheKey = Get-ActiveSqlSchemaCacheKey
        E2EAssertTrue ($Script:SqlSchemaCache.ContainsKey($CacheKey)) "the schema should be cached after a fetch"

        # Warm the index too, so the case proves BOTH caches are dropped rather than only the one the
        # user can see.
        $null = Get-ActiveSqlSchemaModel
        E2EAssertTrue ($Script:SqlSchemaModelCache.ContainsKey($CacheKey)) "the indexed schema should be memoised beside the response"

        $script:E2ECalls.Clear()
        Reset-SqlSchemaCache
        Wait-E2ENoPendingRequests

        E2EAssertEqual 1 (Get-E2ECallCount -MethodLike "POST" -UriLike "*getsqlschema*") "refreshing should fetch the schema again"
        E2EAssertTrue ($Script:SqlSchemaCache.ContainsKey($CacheKey)) "the refreshed response should repopulate the cache"
    }
}
