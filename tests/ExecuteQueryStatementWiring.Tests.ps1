#Requires -Version 7.0
# Issue #151: the wiring between the editor and the pipeline. Invoke-ExecuteQuery splits the text that
# is about to run into statements and passes them to Invoke-OmadaExecutePipeline, which executes each
# one as its own query.
#
# This asserts the HANDOVER, which is the part neither of the other two suites can see:
# Get-SqlScriptStatement.Tests.ps1 proves the split itself, Invoke-OmadaExecutePipeline.Tests.ps1
# proves what the pipeline does with the statements it is given, and nothing proved that the thing the
# editor produced actually arrives there. A split that was never passed on, or one computed from the
# wrong text, would leave both of those suites green and the feature broken.
#
# In its own file rather than appended to Invoke-ExecuteQuery.Tests.ps1 on purpose: this needs a
# successful editor read and a real parser, where that file's fixture is built for the completion's
# downstream halves and is relied on by 70 tests.
#
# The real Get-SqlScriptStatement and the real, pinned ScriptDom are used rather than a stub. A stubbed
# splitter would assert only that one function calls another, which is the one thing here that could
# not plausibly break on its own.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PSScriptRoot -ChildPath "ScriptDomTestAssembly.ps1")

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Format-ElapsedTime.ps1")
    . (Join-Path $PrivatePath -ChildPath "Set-TextBlockText.ps1")
    . (Join-Path $PrivatePath -ChildPath "Set-ButtonText.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-ActiveExecuteQueryRequest.ps1")
    . (Join-Path $PrivatePath -ChildPath "Set-ExecuteQueryButtonState.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-ContainedErrorLog.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-TabMessage.ps1")
    . (Join-Path $PrivatePath -ChildPath "Set-TabStatusMessage.ps1")
    # The real splitter and the real parse behind it: this suite exists to prove what reaches the
    # pipeline, so the thing that produces it is not stubbed.
    . (Join-Path $PrivatePath -ChildPath "Get-SqlParserType.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlScriptFragment.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlScriptStatement.ps1")

    # Issue #152 put a gate between the split and the dispatch, so the real one is loaded here rather
    # than stubbed: these cases assert what the pipeline is handed, and a stub would let the two
    # drift. Every script below names no database, so the gate returns None without ever reaching the
    # data connection dropdown - which is why no WPF stub is needed for it.
    . (Join-Path $PrivatePath -ChildPath "Get-SqlFragmentDescendant.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlDatabaseReference.ps1")
    . (Join-Path $PrivatePath -ChildPath "ConvertTo-UnqualifiedSqlQuery.ps1")
    . (Join-Path $PrivatePath -ChildPath "Resolve-DataConnectionReference.ps1")
    . (Join-Path $PrivatePath -ChildPath "Resolve-SqlStatementTarget.ps1")

    . (Join-Path $PrivatePath -ChildPath "Invoke-ExecuteQuery.ps1")
    # An execute forgets a reused fetch of the selected query (Get-RecentSqlQueryObject.ps1).
    . (Join-Path $PrivatePath -ChildPath "Get-RecentSqlQueryObject.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $script:ScriptDomPath = Install-ScriptDomForTest -RepositoryRoot $ParentPath

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog,
            [switch]$TabScoped
        )
        process { }
    }

    function Get-ActiveTabSession { return $Script:TestTabSession }
    function Get-TabControlSessions { return [pscustomobject]@{ SelectedItem = $Script:TestTabSession.TabItem } }
    function Test-ConnectionRequirements { return $true }
    function Build-OmadaRequestParameter { return @{ SessionKey = "pool" } }

    # The validation gate is switched off for these tests. It is thoroughly covered by the issue #61
    # suites, it would drag the three diagnostic passes into this fixture, and it has no bearing on
    # which statements reach the pipeline - the gate reads the same text and changes none of it.
    function Get-SqlValidationSetting {
        return [pscustomobject]@{
            Enabled                = $false
            SchemaEnabled          = $false
            OmadaEnabled           = $false
            WarnOnExecuteWithErrors = $false
        }
    }

    # Captures the completion the editor read would have invoked, so a test can drive it with a
    # successful task of its own making. The same technique the faulted-read suite in
    # Invoke-ExecuteQuery.Tests.ps1 uses.
    function Invoke-ExecuteScriptWithResultAsync {
        param($ScriptToExecute, $OnCompletedScriptBlock)
        $script:CapturedCompletion = $OnCompletedScriptBlock
    }

    function Invoke-ExecuteScriptAsync {
        param($ScriptToExecute)
    }

    # The dispatch the context is handed to. Recorded, and answered with a non-null pending item so
    # Invoke-ExecuteQuery takes the background path and returns - the inline fallback would run the
    # whole pipeline, which is another suite's subject.
    function Invoke-OmadaPSWebRequestWrapperAsync {
        param($Description, $PipelineContext, $Context, $OnResultScriptBlock)
        $script:DispatchedContext = $PipelineContext
        return [pscustomobject]@{ Id = "pending-1" }
    }

    function script:Initialize-WiringTestState {
        $script:CapturedCompletion = $null
        $script:DispatchedContext = $null

        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test"; InstanceGuid = "abc" }
        $Script:ConnectionStatus = $true
        $Script:PendingWebViewCompletions = [System.Collections.Generic.List[object]]::new()

        $Script:TestTabSession = [pscustomobject]@{
            Id            = "tab-A"
            TabItem       = "item-A"
            Elements      = @{
                TextBoxQueryMessages      = [pscustomobject]@{ Text = "" }
                TabControlQueryOutput     = [pscustomobject]@{ SelectedIndex = 0 }
                TextBlockStatusBarMessage = [pscustomobject]@{ Name = "TextBlockStatusBarMessage"; Text = "" }
            }
            QueryMessages = [System.Collections.Generic.List[string]]::new()
        }

        $Script:AppConfig = [PSCustomObject]@{
            CurrentSqlQuery       = [PSCustomObject]@{ DoId = 100; DisplayName = "TestQuery"; FullName = "TestQuery - 100" }
            CurrentDataConnection = [PSCustomObject]@{ DoId = "42" }
            BaseUrl               = "https://tenant.omada.cloud"
        }

        # QueryText and CurrentQueryText are declared here and not only in the shared fixture for a
        # concrete reason: the completion's first act is to WRITE $Script:RunTimeData.QueryText, and
        # assigning a property a [PSCustomObject] does not already have throws. That exception would be
        # swallowed by the completion's own catch, the context would never be assembled, and these
        # tests would pass while proving nothing at all.
        $Script:RunTimeData = [PSCustomObject]@{
            QueryText        = $null
            CurrentQueryText = "SELECT 1"
            QueryResult      = $null
            StopWatch        = [System.Diagnostics.Stopwatch]::StartNew()
            CurrentSqlQuery  = [PSCustomObject]@{ DisplayName = "TestQuery" }
            LastRowsRead     = 0
            # Declared pre-emptively (issue #151). Nothing in this suite reaches
            # Complete-ExecuteQueryResult today - the async wrapper is stubbed and the cases return at
            # the dispatch - but that function writes the per-statement outcomes here, and assigning a
            # property a [PSCustomObject] does not already have THROWS into the caller's own catch.
            # That silently cost 25 cases in Invoke-ExecuteQuery.Tests.ps1, so the shape is matched
            # here rather than waiting for the first case that drives the completion to find it.
            LastStatementOutcome = $null
        }

        $Script:MainForm = @{
            Elements = @{
                ButtonSaveQuery             = [PSCustomObject]@{ IsEnabled = $false }
                ButtonExecuteQuery          = [PSCustomObject]@{ IsEnabled = $false; ToolTip = "Execute" }
                ButtonExecuteQueryText      = [PSCustomObject]@{ Name = "ButtonExecuteQueryText"; Text = "_Execute" }
                ButtonExecuteQueryImage     = [PSCustomObject]@{ Name = "ButtonExecuteQueryImage"; Text = [char]0xE768 }
                TextBoxDisplayName          = [PSCustomObject]@{ Text = "TestQuery" }
                TextBlockStatusBarRows      = [PSCustomObject]@{ Name = "TextBlockStatusBarRows"; Text = "-" }
                TextBlockStatusBarQueryTime = [PSCustomObject]@{ Name = "TextBlockStatusBarQueryTime"; Text = "-" }
            }
        }
    }

    function script:Invoke-EditorRead {
        # Drives one execute: Invoke-ExecuteQuery registers the completion, then the completion runs
        # against an editor payload of the test's choosing - the same JSON shape the Monaco script
        # returns.
        param(
            [string]$FullText,
            $SelectedText = $null,
            [int]$SelectionStartLine = 1,
            [int]$SelectionStartColumn = 1
        )

        Invoke-ExecuteQuery

        $Private:Payload = @{
            fullText             = $FullText
            selectedText         = $SelectedText
            selectionStartLine   = $SelectionStartLine
            selectionStartColumn = $SelectionStartColumn
        } | ConvertTo-Json

        $Script:Task = [pscustomobject]@{ Status = "RanToCompletion"; Result = $Private:Payload }

        & $script:CapturedCompletion
    }
}

Describe "Invoke-ExecuteQuery hands the pipeline one statement per statement (#151)" {

    BeforeEach {
        Initialize-WiringTestState

        if ([string]::IsNullOrWhiteSpace($script:ScriptDomPath)) {
            Set-ItResult -Inconclusive -Because "the pinned ScriptDom assembly could not be resolved on this agent"
        }
    }

    It "dispatches a context at all, so the assertions below are about a real handover" {
        # Guards the fixture itself. Every test here reads $script:DispatchedContext, and a completion
        # that threw on its way to the dispatch would leave it null and make the rest of this file
        # vacuously true.
        Invoke-EditorRead -FullText "SELECT 1"

        $script:DispatchedContext | Should -Not -BeNullOrEmpty
        $script:DispatchedContext.QueryDoId | Should -Be 100
    }

    It "passes both statements of a two-statement script, in editor order" {
        # The acceptance criterion, at the handover: nothing selected, so every statement in the editor
        # runs, each as its own query.
        Invoke-EditorRead -FullText "SELECT 1;`r`nSELECT 2;"

        @($script:DispatchedContext.Statements).Count | Should -Be 2
        @($script:DispatchedContext.Statements | ForEach-Object { $_.Ordinal }) | Should -Be @(1, 2)
        $script:DispatchedContext.Statements[0].Text | Should -Match 'SELECT\s+1'
        $script:DispatchedContext.Statements[1].Text | Should -Match 'SELECT\s+2'
    }

    It "passes exactly one statement for a single-statement script" {
        # Which is what keeps an ordinary execute identical to what it was before this issue.
        Invoke-EditorRead -FullText "SELECT TOP 10 * FROM dbo.Thing"

        @($script:DispatchedContext.Statements).Count | Should -Be 1
    }

    It "splits the SELECTION, not the whole editor, when there is one" {
        # The decision worth reviewing. The selection's own text is split rather than editor offsets
        # being mapped onto the model, so selecting one statement out of three executes exactly one
        # query - and no offset arithmetic exists to get wrong.
        Invoke-EditorRead -FullText "SELECT 1;`r`nSELECT 2;`r`nSELECT 3;" -SelectedText "SELECT 2;" -SelectionStartLine 2

        @($script:DispatchedContext.Statements).Count | Should -Be 1
        $script:DispatchedContext.Statements[0].Text | Should -Match 'SELECT\s+2'
    }

    It "passes every statement inside a multi-statement selection" {
        # Selecting two of three runs those two, in editor order.
        Invoke-EditorRead -FullText "SELECT 1;`r`nSELECT 2;`r`nSELECT 3;" -SelectedText "SELECT 2;`r`nSELECT 3;" -SelectionStartLine 2

        @($script:DispatchedContext.Statements).Count | Should -Be 2
        $script:DispatchedContext.Statements[0].Text | Should -Match 'SELECT\s+2'
        $script:DispatchedContext.Statements[1].Text | Should -Match 'SELECT\s+3'
    }

    It "still carries the selection text, so the pipeline runs against the temporary object" {
        # Statements say WHAT to run; SelectionText is still what tells the pipeline that the text is
        # not the saved query. Dropping it would make an executed selection run the saved query
        # instead - silently the wrong SQL.
        Invoke-EditorRead -FullText "SELECT 1;`r`nSELECT 2;" -SelectedText "SELECT 2;" -SelectionStartLine 2

        $script:DispatchedContext.SelectionText | Should -Match 'SELECT\s+2'
    }

    It "passes a single statement for a script the parser cannot understand" {
        # The safety rule of issue #151: a script that defeats the parser is executed as one query,
        # exactly as today, rather than being mis-split into fragments that are not valid SQL.
        Invoke-EditorRead -FullText "SELECT FROM WHERE ((("

        @($script:DispatchedContext.Statements).Count | Should -Be 1
        $script:DispatchedContext.Statements[0].Text | Should -Be "SELECT FROM WHERE ((("
    }

    It "does not split on a semicolon inside a string literal on the way to the pipeline" {
        # The end-to-end version of the reason ScriptDom is used at all.
        Invoke-EditorRead -FullText "SELECT 'a;b' AS Value"

        @($script:DispatchedContext.Statements).Count | Should -Be 1
    }

    It "leaves the rest of the pipeline context untouched" {
        # Statements is an addition, not a replacement: everything the chain needed before #151 still
        # has to arrive, or the save and the temporary object break in ways no test here would see.
        Invoke-EditorRead -FullText "SELECT 1;`r`nSELECT 2;"

        $script:DispatchedContext.BaseUrl | Should -Be "https://tenant.omada.cloud"
        $script:DispatchedContext.DataConnectionDoId | Should -Be "42"
        $script:DispatchedContext.TempName | Should -Be "TMP_abc"
        $script:DispatchedContext.DisplayName | Should -Be "TestQuery"
        $script:DispatchedContext.SkipSave | Should -BeFalse
    }
}
