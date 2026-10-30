#Requires -Version 7.0
# Tests for running the client-side validation passes on a worker runspace (issue #185).
#
# The validation used to run on the WPF dispatcher after every pause in typing, which froze the
# window. These tests run the REAL worker: a real runspace pool, the real pass files dot-sourced from
# disk, the real ScriptDom - because what can break here is exactly what a stub would hide: a file the
# worker does not load, a function the worker cannot see, an object that does not survive the trip.

BeforeDiscovery {
    # One query that produces a diagnostic from each of the three passes, and one with a syntax
    # error - which the schema and Omada passes skip, so it needs its own case.
    $Script:Corpus = @(
        "SELECT p.Id, p.Missing FROM dbo.Person p JOIN dbo.Contract c ON c.PersonId = p.Id; SELECT COUNT(*) FROM dbo.Unknown; UPDATE dbo.Person SET DisplayName = 'x'"
        "SELECT a, FROM dbo.Person"
    )
}

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Script:Corpus = @(
        "SELECT p.Id, p.Missing FROM dbo.Person p JOIN dbo.Contract c ON c.PersonId = p.Id; SELECT COUNT(*) FROM dbo.Unknown; UPDATE dbo.Person SET DisplayName = 'x'"
        "SELECT a, FROM dbo.Person"
    )
    $Script:PrivatePath = [System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private")

    . (Join-Path $PSScriptRoot -ChildPath "ScriptDomTestAssembly.ps1")

    . (Join-Path $Script:PrivatePath -ChildPath "Get-OmadaPipelineWorkerFunction.ps1")
    foreach ($WorkerFile in $Script:SqlDiagnosticWorkerFile) {
        . (Join-Path $Script:PrivatePath -ChildPath $WorkerFile)
    }
    . (Join-Path $Script:PrivatePath -ChildPath "Get-SqlSchemaModel.ps1")
    . (Join-Path $Script:PrivatePath -ChildPath "Start-SqlDiagnosticBackground.ps1")
    . (Join-Path $Script:PrivatePath -ChildPath "ConvertTo-JavaScriptLiteral.ps1")
    . (Join-Path $Script:PrivatePath -ChildPath "ConvertTo-EditorDiagnosticScript.ps1")

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType = "INFO",
            $ErrorObject,
            [switch]$SkipDialog,
            [switch]$TabScoped
        )
        process { }
    }

    $Script:RunTimeConfig = [PSCustomObject]@{ ModuleFolder = (Join-Path $ParentPath "src") }

    $script:ScriptDomPath = Install-ScriptDomForTest -RepositoryRoot $ParentPath

    $Script:Setting = [PSCustomObject]@{
        Enabled                 = $true
        SchemaEnabled           = $true
        OmadaEnabled            = $true
        DebounceMilliseconds    = 400
        WarnOnExecuteWithErrors = $true
        ParserVersion           = $null
        RuleSeverity            = $null
    }

    $Script:SchemaModel = Get-SqlSchemaModel -NoLog -SchemaResponse ([PSCustomObject]@{
            d = [PSCustomObject][ordered]@{
                "dbo.Person"   = @("Id int", "DisplayName nvarchar(100)", "ManagerId int")
                "dbo.Contract" = @("Id int", "PersonId int", "ValidTo datetime")
            }
        })

    function Wait-SqlDiagnosticPool {
        $Deadline = [DateTime]::UtcNow.AddSeconds(30)
        while ([DateTime]::UtcNow -lt $Deadline) {
            $Pool = Initialize-SqlDiagnosticPool
            if ($null -ne $Pool) {
                return $Pool
            }
            Start-Sleep -Milliseconds 50
        }
        throw "The validation worker pool did not open within 30 seconds."
    }

    function Wait-PendingCompletion {
        param($Pending)
        if (-not $Pending.Task.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds(60))) {
            throw "The validation worker did not finish within 60 seconds."
        }
    }

    function ConvertTo-DiagnosticSignature {
        param($Diagnostic)
        return @($Diagnostic | ForEach-Object { "{0}|{1}:{2}-{3}:{4}|{5}|{6}" -f $_.Source, $_.Line, $_.Column, $_.EndLine, $_.EndColumn, $_.Severity, $_.Message })
    }

    function New-TestTab {
        param([string]$Id = ([guid]::NewGuid().ToString()))
        return [PSCustomObject]@{ Id = $Id; DisplayName = "Tab $Id" }
    }
}

AfterAll {
    Close-SqlDiagnosticPool
}

Describe 'The validation worker''s file list' -Tag 'Unit' {
    # The worker runspace has never loaded this module. It sees exactly the files it dot-sources, so a
    # pass that starts calling a function from a file not on the list fails inside the worker - where
    # the passes' own try/catch turns it into "no diagnostics", silently. Derived from the source
    # here, so that change fails a test instead.

    It 'Should list exactly the files Get-SqlDiagnostic reaches when it is handed the setting and both models' {
        $Definition = @{}
        foreach ($File in Get-ChildItem -Path (Join-Path $Script:PrivatePath "*.ps1")) {
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            foreach ($Function in $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
                $Definition[$Function.Name.ToLowerInvariant()] = [PSCustomObject]@{ File = $File.Name; Ast = $Function }
            }
        }

        # Not followed, and why:
        #   Write-LogOutput            the worker defines its own no-op
        #   Get-SqlValidationSetting   the setting is handed over (-Setting is bound)
        #   Get-ActiveSqlSchemaModel   the model is handed over (-SchemaModel is bound)
        #   Get-CachedSqlSchemaModelByDatabase   likewise (-DatabaseSchemaModel is bound)
        $NotFollowed = @("write-logoutput", "get-sqlvalidationsetting", "get-activesqlschemamodel", "get-cachedsqlschemamodelbydatabase")

        $Reached = [System.Collections.Generic.HashSet[string]]::new()
        $Queue = [System.Collections.Generic.Queue[string]]::new()
        $Queue.Enqueue("get-sqldiagnostic")
        while ($Queue.Count -gt 0) {
            $Name = $Queue.Dequeue()
            if (-not $Definition.ContainsKey($Name) -or -not $Reached.Add($Name)) {
                continue
            }
            foreach ($Command in $Definition[$Name].Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $Called = $Command.GetCommandName()
                if ($null -ne $Called -and $NotFollowed -notcontains $Called.ToLowerInvariant()) {
                    $Queue.Enqueue($Called.ToLowerInvariant())
                }
            }
        }

        $Needed = @($Reached | ForEach-Object { $Definition[$_].File } | Sort-Object -Unique)
        @($Script:SqlDiagnosticWorkerFile | Sort-Object -Unique) | Should -Be $Needed
    }

    It 'Should be shipped by the build, through the worker runtime file list' {
        # The release build merges every function into one file and copies only
        # Get-OmadaWorkerRuntimeFile as loose files - see the build guard in
        # Get-OmadaPipelineWorkerFunction.Tests.ps1. A worker file missing from it would make every
        # validation in the released module fall back to the UI thread.
        $Shipped = Get-OmadaWorkerRuntimeFile
        foreach ($File in $Script:SqlDiagnosticWorkerFile) {
            $Shipped | Should -Contain $File
        }
    }

    It 'Should hand the worker the setting and both models, which is what makes the list above complete' {
        $Source = Get-Content -Path (Join-Path $Script:PrivatePath "Start-SqlDiagnosticBackground.ps1") -Raw
        $Source | Should -Match 'Get-SqlDiagnostic -SqlText \$SqlText -Setting \$Setting -SchemaModel \$SchemaModel -DatabaseSchemaModel \$DatabaseSchemaModel'
    }
}

Describe 'Start-SqlDiagnosticBackground' -Tag 'Unit' {

    BeforeAll {
        if ($null -ne $script:ScriptDomPath) {
            $null = Wait-SqlDiagnosticPool
        }
    }

    BeforeEach {
        if ($null -eq $script:ScriptDomPath) {
            Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
        }
        $Script:PendingWebViewCompletions = [System.Collections.Generic.List[object]]::new()
        $Script:SqlValidationInFlight = @{}
    }

    It 'Should produce exactly the diagnostics the inline path produces: <_>' -ForEach $Script:Corpus {
        $Tab = New-TestTab
        $Inline = Get-SqlDiagnostic -SqlText $_ -Setting $Script:Setting -SchemaModel $Script:SchemaModel -DatabaseSchemaModel @{}

        $Pending = Start-SqlDiagnosticBackground -TabSession $Tab -SqlText $_ -Setting $Script:Setting -SchemaModel $Script:SchemaModel -DatabaseSchemaModel @{}
        $Pending | Should -Not -BeNullOrEmpty
        Wait-PendingCompletion -Pending $Pending
        $Outcome = Complete-SqlDiagnosticBackground -Pending $Pending

        $Outcome.Apply | Should -BeTrue
        @($Inline.Diagnostic).Count | Should -BeGreaterThan 0 -Because "an empty corpus would pass this comparison for the wrong reason"
        ConvertTo-DiagnosticSignature $Outcome.Diagnostic | Should -Be (ConvertTo-DiagnosticSignature $Inline.Diagnostic)
    }

    It 'Should cover all three passes with the corpus above' {
        # So the comparison above proves the worker can see every pass, not just the parser.
        $Source = @($Script:Corpus | ForEach-Object {
                (Get-SqlDiagnostic -SqlText $_ -Setting $Script:Setting -SchemaModel $Script:SchemaModel -DatabaseSchemaModel @{}).Diagnostic.Source
            } | Sort-Object -Unique)

        $Source | Should -Contain "T-SQL syntax"
        $Source | Should -Contain "SQL schema"
        $Source | Should -Contain "Omada compatibility"
    }

    It 'Should queue an item the poll timer drains, without the properties that would make it look like a query' {
        $Tab = New-TestTab
        $Pending = Start-SqlDiagnosticBackground -TabSession $Tab -SqlText "SELECT 1 AS a" -Setting $Script:Setting -SchemaModel $Script:SchemaModel

        $Script:PendingWebViewCompletions | Should -Contain $Pending
        $Pending.TabSession | Should -Be $Tab
        $Pending.Description | Should -Be $Script:SqlValidationRequestDescription
        $Pending.OnCompletedScriptBlock | Should -BeOfType [scriptblock]

        # The poll timer's closed-tab check (and the dispose that goes with it) keys on this.
        $Pending.IsBackgroundRequest | Should -BeTrue

        # The elapsed-time indicator, Remove-PendingBackgroundRequest and the "is a query running"
        # check all select on StartedUtc. A validation is none of those things.
        $Pending.PSObject.Properties.Name | Should -Not -Contain "StartedUtc"

        Wait-PendingCompletion -Pending $Pending
        $null = Complete-SqlDiagnosticBackground -Pending $Pending
    }

    It 'Should push the markers to the editor when the poll timer runs its completion block' {
        # Driven the way MainForm.Definition.ps1's Tick drives every queued item: the block is invoked
        # with the item itself as its argument, after the owning tab has been made active.
        $Tab = New-TestTab
        $Pushed = [System.Collections.Generic.List[string]]::new()
        function Invoke-ExecuteScriptAsync { param($ScriptToExecute) $Pushed.Add([string]$ScriptToExecute) }

        $Pending = Start-SqlDiagnosticBackground -TabSession $Tab -SqlText "SELECT p.Missing FROM dbo.Person p" -Setting $Script:Setting -SchemaModel $Script:SchemaModel
        Wait-PendingCompletion -Pending $Pending
        & $Pending.OnCompletedScriptBlock $Pending

        $Pushed.Count | Should -Be 1
        $Pushed[0] | Should -Match '^setDiagnostics\(\[\{'
        $Pushed[0] | Should -Match 'Missing'
    }

    It 'Should push nothing when the poll timer completes a superseded item' {
        $Tab = New-TestTab
        $Pushed = [System.Collections.Generic.List[string]]::new()
        function Invoke-ExecuteScriptAsync { param($ScriptToExecute) $Pushed.Add([string]$ScriptToExecute) }

        $First = Start-SqlDiagnosticBackground -TabSession $Tab -SqlText "SELECT p.Missing FROM dbo.Person p" -Setting $Script:Setting -SchemaModel $Script:SchemaModel
        $Second = Start-SqlDiagnosticBackground -TabSession $Tab -SqlText "SELECT 1 AS a" -Setting $Script:Setting -SchemaModel $Script:SchemaModel
        & $First.OnCompletedScriptBlock $First

        $Pushed.Count | Should -Be 0

        Wait-PendingCompletion -Pending $Second
        $null = Complete-SqlDiagnosticBackground -Pending $Second
    }

    It 'Should return immediately rather than waiting for the worker' {
        # Not a timing assertion on the passes - those vary by machine - but on the shape: the caller
        # gets a pending item back before the result exists.
        $Tab = New-TestTab
        $Sql = ((1..40) | ForEach-Object { "SELECT p.Id, p.DisplayName FROM dbo.Person p JOIN dbo.Contract c ON c.PersonId = p.Id WHERE p.Id IN (SELECT x.Id FROM dbo.Person x);" }) -join "`n"

        $Pending = Start-SqlDiagnosticBackground -TabSession $Tab -SqlText $Sql -Setting $Script:Setting -SchemaModel $Script:SchemaModel

        $Pending.Task.IsCompleted | Should -BeFalse
        Wait-PendingCompletion -Pending $Pending
        $null = Complete-SqlDiagnosticBackground -Pending $Pending
    }

    Context 'Only the latest result for a tab is applied' {

        It 'Should stop the earlier validation of the same tab when a newer one starts' {
            $Tab = New-TestTab
            $First = Start-SqlDiagnosticBackground -TabSession $Tab -SqlText "SELECT 1 AS a" -Setting $Script:Setting -SchemaModel $Script:SchemaModel
            $Second = Start-SqlDiagnosticBackground -TabSession $Tab -SqlText "SELECT 2 AS b" -Setting $Script:Setting -SchemaModel $Script:SchemaModel

            $First.IsCancelled | Should -BeTrue
            $Script:PendingWebViewCompletions | Should -Not -Contain $First
            $Script:PendingWebViewCompletions | Should -Contain $Second

            (Complete-SqlDiagnosticBackground -Pending $First).Apply | Should -BeFalse -Because "its text is not in the editor any more"

            Wait-PendingCompletion -Pending $Second
            (Complete-SqlDiagnosticBackground -Pending $Second).Apply | Should -BeTrue
        }

        It 'Should not apply a result that finished after a newer validation started' {
            # The second line of defence: the item may already have been drained off the queue when the
            # newer one starts. Simulated by holding on to the first and completing it late.
            $Tab = New-TestTab
            $First = Start-SqlDiagnosticBackground -TabSession $Tab -SqlText "SELECT 1 AS a" -Setting $Script:Setting -SchemaModel $Script:SchemaModel
            $Script:SqlValidationInFlight[$Tab.Id] = [PSCustomObject]@{ Shell = $null; IsCancelled = $false }

            Wait-PendingCompletion -Pending $First
            (Complete-SqlDiagnosticBackground -Pending $First).Apply | Should -BeFalse
        }

        It 'Should leave another tab''s validation alone' {
            $TabA = New-TestTab
            $TabB = New-TestTab
            $A = Start-SqlDiagnosticBackground -TabSession $TabA -SqlText "SELECT 1 AS a" -Setting $Script:Setting -SchemaModel $Script:SchemaModel
            $B = Start-SqlDiagnosticBackground -TabSession $TabB -SqlText "SELECT 2 AS b" -Setting $Script:Setting -SchemaModel $Script:SchemaModel

            $A.IsCancelled | Should -BeFalse
            Wait-PendingCompletion -Pending $A
            Wait-PendingCompletion -Pending $B
            (Complete-SqlDiagnosticBackground -Pending $A).Apply | Should -BeTrue
            (Complete-SqlDiagnosticBackground -Pending $B).Apply | Should -BeTrue
        }

        It 'Should not apply a result twice' {
            $Tab = New-TestTab
            $Pending = Start-SqlDiagnosticBackground -TabSession $Tab -SqlText "SELECT 1 AS a" -Setting $Script:Setting -SchemaModel $Script:SchemaModel
            Wait-PendingCompletion -Pending $Pending

            (Complete-SqlDiagnosticBackground -Pending $Pending).Apply | Should -BeTrue
            (Complete-SqlDiagnosticBackground -Pending $Pending).Apply | Should -BeFalse
        }
    }

    Context 'Stop-SqlDiagnosticBackground' {

        It 'Should take the item off the queue and mark it cancelled' {
            $Tab = New-TestTab
            $Pending = Start-SqlDiagnosticBackground -TabSession $Tab -SqlText "SELECT 1 AS a" -Setting $Script:Setting -SchemaModel $Script:SchemaModel

            Stop-SqlDiagnosticBackground -TabSession $Tab

            $Pending.IsCancelled | Should -BeTrue
            $Script:PendingWebViewCompletions | Should -Not -Contain $Pending
            $Script:SqlValidationInFlight.ContainsKey($Tab.Id) | Should -BeFalse
        }

        It 'Should do nothing for a tab with no validation running' {
            { Stop-SqlDiagnosticBackground -TabSession (New-TestTab) } | Should -Not -Throw
            { Stop-SqlDiagnosticBackground -TabSession $null } | Should -Not -Throw
        }

        It 'Should leave the pool usable for the next validation' {
            $Tab = New-TestTab
            $null = Start-SqlDiagnosticBackground -TabSession $Tab -SqlText "SELECT 1 AS a" -Setting $Script:Setting -SchemaModel $Script:SchemaModel
            Stop-SqlDiagnosticBackground -TabSession $Tab

            $Next = Start-SqlDiagnosticBackground -TabSession $Tab -SqlText "SELECT p.Missing FROM dbo.Person p" -Setting $Script:Setting -SchemaModel $Script:SchemaModel
            Wait-PendingCompletion -Pending $Next
            $Outcome = Complete-SqlDiagnosticBackground -Pending $Next

            $Outcome.Apply | Should -BeTrue
            @($Outcome.Diagnostic).Count | Should -Be 1
        }
    }

    Context 'A worker that fails' {

        It 'Should clear the markers rather than leave stale ones' {
            # The rule the inline path has always followed: a check that could not run must not leave
            # an earlier check's squiggles on screen.
            $Tab = New-TestTab
            $Shell = [powershell]::Create()
            [void]$Shell.AddScript({ throw "the worker broke" })
            $Pending = [PSCustomObject]@{
                Task        = $Shell.BeginInvoke()
                Shell       = $Shell
                TabSession  = $Tab
                IsCancelled = $false
            }
            $Script:SqlValidationInFlight[$Tab.Id] = $Pending
            Wait-PendingCompletion -Pending $Pending

            $Outcome = Complete-SqlDiagnosticBackground -Pending $Pending

            $Outcome.Apply | Should -BeTrue
            @($Outcome.Diagnostic).Count | Should -Be 0
        }

        It 'Should clear the markers when the passes report they could not run' {
            $Tab = New-TestTab
            $Setting = $Script:Setting.PSObject.Copy()
            $Setting.ParserVersion = "TSql1Parser"
            $Pending = Start-SqlDiagnosticBackground -TabSession $Tab -SqlText "SELECT 1 AS a" -Setting $Setting -SchemaModel $Script:SchemaModel
            Wait-PendingCompletion -Pending $Pending

            $Outcome = Complete-SqlDiagnosticBackground -Pending $Pending

            $Outcome.Apply | Should -BeTrue
            @($Outcome.Diagnostic).Count | Should -Be 0
        }
    }
}

Describe 'Falling back to the UI thread' -Tag 'Unit' {
    # Issue #185 acceptance criterion 3: no worker means validation as it always was, not no
    # validation. Start returns $null and the caller validates inline (Update-SqlSyntaxDiagnostic).

    BeforeEach {
        $Script:PendingWebViewCompletions = [System.Collections.Generic.List[object]]::new()
        $Script:SqlValidationInFlight = @{}
    }

    It 'Should return $null while the pool is still opening' {
        $Saved = $Script:SqlDiagnosticPool
        try {
            $Script:SqlDiagnosticPool = $null
            Start-SqlDiagnosticBackground -TabSession (New-TestTab) -SqlText "SELECT 1" -Setting $Script:Setting | Should -BeNullOrEmpty
            $Script:PendingWebViewCompletions.Count | Should -Be 0
        }
        finally {
            Close-SqlDiagnosticPool
            $Script:SqlDiagnosticPool = $Saved
        }
    }

    It 'Should open the pool in the background rather than on the caller''s thread' {
        $Saved = $Script:SqlDiagnosticPool
        try {
            $Script:SqlDiagnosticPool = $null
            Initialize-SqlDiagnosticPool | Should -BeNullOrEmpty
            $Script:SqlDiagnosticPool | Should -Not -BeNullOrEmpty
            $Script:SqlDiagnosticPool.RunspacePoolStateInfo.State | Should -BeIn @("BeforeOpen", "Opening", "Opened")
        }
        finally {
            Close-SqlDiagnosticPool
            $Script:SqlDiagnosticPool = $Saved
        }
    }

    It 'Should return $null when a worker file is missing' {
        $null = Wait-SqlDiagnosticPool
        $Saved = $Script:SqlDiagnosticWorkerFile
        try {
            $Script:SqlDiagnosticWorkerFile = @($Saved) + "Does-NotExist.ps1"
            Start-SqlDiagnosticBackground -TabSession (New-TestTab) -SqlText "SELECT 1" -Setting $Script:Setting | Should -BeNullOrEmpty
            $Script:PendingWebViewCompletions.Count | Should -Be 0
        }
        finally {
            $Script:SqlDiagnosticWorkerFile = $Saved
        }
    }

    It 'Should return $null when there is no completion queue to put the result on' {
        $Script:PendingWebViewCompletions = $null
        Start-SqlDiagnosticBackground -TabSession (New-TestTab) -SqlText "SELECT 1" -Setting $Script:Setting | Should -BeNullOrEmpty
    }

    It 'Should reopen a pool that has been closed' {
        $null = Wait-SqlDiagnosticPool
        $Script:SqlDiagnosticPool.Close()

        Initialize-SqlDiagnosticPool | Should -BeNullOrEmpty -Because "a fresh pool opens in the background"
        Wait-SqlDiagnosticPool | Should -Not -BeNullOrEmpty
    }
}

Describe 'Close-SqlDiagnosticPool' -Tag 'Unit' {
    It 'Should close the pool and forget it' {
        $null = Wait-SqlDiagnosticPool
        $Pool = $Script:SqlDiagnosticPool

        Close-SqlDiagnosticPool

        $Script:SqlDiagnosticPool | Should -BeNullOrEmpty
        $Pool.RunspacePoolStateInfo.State | Should -BeIn @("Closed", "Closing")
    }

    It 'Should do nothing when no pool was opened' {
        $Script:SqlDiagnosticPool = $null
        { Close-SqlDiagnosticPool } | Should -Not -Throw
    }
}
