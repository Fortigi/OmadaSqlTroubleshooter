#Requires -Version 7.0
# Tests for the two halves issue #40 split out of Invoke-ExecuteQuery's completion block:
# Reset-ExecuteQueryUiState (the teardown) and Complete-ExecuteQueryResult (everything that happens
# once a result is in hand). Both are UI-thread-only and are now reached from three places - the
# inline path, the background completion, and the failure paths - so they are worth asserting
# directly rather than only through the E2E suite, which does not run in CI.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-LogResultShape.ps1")
    . (Join-Path $PrivatePath -ChildPath "Set-TextBlockText.ps1")
    . (Join-Path $PrivatePath -ChildPath "Invoke-ExecuteQuery.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { }
    }

    $script:RemovedQueryObjects = [System.Collections.Generic.List[object]]::new()
    function Remove-SqlQueryObject {
        param($DoId)
        $script:RemovedQueryObjects.Add($DoId)
    }

    $script:ConfigWrites = [System.Collections.Generic.List[object]]::new()
    function Set-ConfigProperty {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$Property
        )
        process { $script:ConfigWrites.Add([pscustomobject]@{ Property = $Property; Value = $InputObject }) }
    }

    $script:QueryListRefreshes = 0
    function Update-QueryList {
        param([switch]$ForceRefresh)
        $script:QueryListRefreshes++
    }

    function Invoke-SanitizeJsonKeys {
        param([Parameter(ValueFromPipeline = $true)]$InputObject)
        process { $InputObject }
    }

    function script:New-PopupStub {
        $Popup = [pscustomobject]@{ Closed = $false }
        $Popup | Add-Member -MemberType ScriptMethod -Name Close -Value { $this.Closed = $true }
        return $Popup
    }

    function script:Initialize-ExecuteQueryTestState {
        $script:RemovedQueryObjects.Clear()
        $script:ConfigWrites.Clear()
        $script:QueryListRefreshes = 0

        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
        $Script:PopupWindowExecuteQuery = New-PopupStub
        $Script:AppConfig = [PSCustomObject]@{
            CurrentSqlQuery = [PSCustomObject]@{ DoId = 100; FullName = "TestQuery - 100" }
        }
        $Script:RunTimeData = [PSCustomObject]@{
            QueryResult     = $null
            StopWatch       = [System.Diagnostics.Stopwatch]::StartNew()
            CurrentSqlQuery = [PSCustomObject]@{ DisplayName = "TestQuery" }
        }
        $Script:MainForm = @{
            Elements = @{
                ButtonSaveQuery             = [PSCustomObject]@{ IsEnabled = $false }
                ButtonExecuteQuery          = [PSCustomObject]@{ IsEnabled = $false }
                ButtonShowOutput            = [PSCustomObject]@{ IsEnabled = $false }
                ButtonSaveOutputFile        = [PSCustomObject]@{ IsEnabled = $false }
                DataGridQueryResult         = [PSCustomObject]@{ ItemsSource = "previous"; AutoGenerateColumns = $false }
                TextBlockStatusBarRows      = [PSCustomObject]@{ Name = "TextBlockStatusBarRows"; Text = "-" }
                TextBlockStatusBarQueryTime = [PSCustomObject]@{ Name = "TextBlockStatusBarQueryTime"; Text = "-" }
                ComboBoxSelectQuery         = [PSCustomObject]@{ Items = [System.Collections.ArrayList]::new(); SelectedItem = $null }
            }
        }
    }

    function script:New-ResultResponse {
        param([int]$RowCount = 2)
        $Rows = @(1..$RowCount | ForEach-Object { [pscustomobject]@{ Col1 = "v$_" } })
        if ($RowCount -eq 0) { $Rows = @() }
        return [pscustomobject]@{ d = [pscustomobject]@{ Records = $RowCount; Rows = $Rows } }
    }
}

Describe "Reset-ExecuteQueryUiState" {
    BeforeEach { Initialize-ExecuteQueryTestState }

    It "re-enables the buttons the execute click disabled" {
        Reset-ExecuteQueryUiState

        $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled | Should -BeTrue
        $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled | Should -BeTrue
    }

    It "closes the 'Executing Query...' popup and forgets it" {
        $Popup = $Script:PopupWindowExecuteQuery

        Reset-ExecuteQueryUiState

        $Popup.Closed | Should -BeTrue
        # Nulled as well as closed: a stale reference would be Close()d a second time by the next
        # execute's teardown.
        $Script:PopupWindowExecuteQuery | Should -BeNullOrEmpty
    }

    It "stops the stopwatch and writes its value to the status bar" {
        Reset-ExecuteQueryUiState

        $Script:RunTimeData.StopWatch.IsRunning | Should -BeFalse
        $Script:MainForm.Elements.TextBlockStatusBarQueryTime.Text | Should -Match '^\d{2}:\d{2}:\d{2}'
    }

    It "can stop the stopwatch without writing a time that would mean nothing" {
        Reset-ExecuteQueryUiState -SkipStatusBarTime

        $Script:RunTimeData.StopWatch.IsRunning | Should -BeFalse
        $Script:MainForm.Elements.TextBlockStatusBarQueryTime.Text | Should -Be "-"
    }

    It "leaves the results grid untouched" {
        # A failed or abandoned execute must not blank a perfectly good previous result.
        Reset-ExecuteQueryUiState

        $Script:MainForm.Elements.DataGridQueryResult.ItemsSource | Should -Be "previous"
    }

    It "does not throw when there is no popup and no stopwatch" {
        $Script:PopupWindowExecuteQuery = $null
        $Script:RunTimeData.StopWatch = $null

        { Reset-ExecuteQueryUiState } | Should -Not -Throw
    }
}

Describe "Complete-ExecuteQueryResult" {
    BeforeEach { Initialize-ExecuteQueryTestState }

    It "binds the rows and reports the record count" {
        Complete-ExecuteQueryResult -QueryResult (New-ResultResponse -RowCount 2) -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId $null

        @($Script:MainForm.Elements.DataGridQueryResult.ItemsSource).Count | Should -Be 2
        $Script:MainForm.Elements.TextBlockStatusBarRows.Text | Should -Be "2 rows"
        $Script:MainForm.Elements.ButtonShowOutput.IsEnabled | Should -BeTrue
        $Script:MainForm.Elements.ButtonSaveOutputFile.IsEnabled | Should -BeTrue
    }

    It "publishes the result so the export and grid-view features can read it" {
        $Response = New-ResultResponse -RowCount 2

        Complete-ExecuteQueryResult -QueryResult $Response -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId $null

        $Script:RunTimeData.QueryResult | Should -Be $Response
    }

    It "clears the grid and says '0 rows' for an empty result" {
        Complete-ExecuteQueryResult -QueryResult (New-ResultResponse -RowCount 0) -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId $null

        $Script:MainForm.Elements.DataGridQueryResult.ItemsSource | Should -BeNullOrEmpty
        $Script:MainForm.Elements.TextBlockStatusBarRows.Text | Should -Be "0 rows"
    }

    It "deletes the temporary selection object" {
        Complete-ExecuteQueryResult -QueryResult (New-ResultResponse) -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId "TMP-42"

        $script:RemovedQueryObjects | Should -Contain "TMP-42"
    }

    It "deletes the temporary object even when the request failed" {
        # A result that never arrived still leaves an object behind on the tenant.
        Complete-ExecuteQueryResult -QueryResult $null -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId "TMP-43"

        $script:RemovedQueryObjects | Should -Contain "TMP-43"
    }

    It "returns the UI to a usable state on every path" {
        Complete-ExecuteQueryResult -QueryResult $null -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId $null

        $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled | Should -BeTrue
        $Script:MainForm.Elements.ButtonSaveQuery.IsEnabled | Should -BeTrue
        $Script:RunTimeData.StopWatch.IsRunning | Should -BeFalse
    }

    It "selects the renamed query in the dropdown instead of clearing the selection" {
        # Regression guard. This block used to test a variable that had never been assigned, so its
        # body was unreachable and the line after it selected $null - executing a renamed query
        # silently emptied the query dropdown. Find-or-create, then select, as Save-Query does.
        Complete-ExecuteQueryResult -QueryResult (New-ResultResponse) -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "RenamedQuery" }) -TempQueryDoId $null

        $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem | Should -Not -BeNullOrEmpty
        $Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem.Content | Should -Be "TestQuery - 100"
    }

    It "reuses an existing dropdown entry rather than adding a duplicate" {
        $Existing = [pscustomobject]@{ Content = "TestQuery - 100" }
        [void]$Script:MainForm.Elements.ComboBoxSelectQuery.Items.Add($Existing)

        Complete-ExecuteQueryResult -QueryResult (New-ResultResponse) -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "RenamedQuery" }) -TempQueryDoId $null

        $Script:MainForm.Elements.ComboBoxSelectQuery.Items.Count | Should -Be 1
        [object]::ReferenceEquals($Script:MainForm.Elements.ComboBoxSelectQuery.SelectedItem, $Existing) | Should -BeTrue
    }

    It "refreshes the query list only when the display name actually changed" {
        Complete-ExecuteQueryResult -QueryResult (New-ResultResponse) -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId $null
        $script:QueryListRefreshes | Should -Be 0

        Complete-ExecuteQueryResult -QueryResult (New-ResultResponse) -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "RenamedQuery" }) -TempQueryDoId $null
        $script:QueryListRefreshes | Should -Be 1
    }

    It "uses the SaveResult it was handed rather than re-reading module state" {
        # The correctness argument for passing it on the pending item: by the time a background
        # response lands, the frame that produced this value has long since returned, and the active
        # tab may be a different one.
        Complete-ExecuteQueryResult -QueryResult (New-ResultResponse) -SaveResult ([pscustomobject]@{ Id = 777; DisplayName = "FromTheRequest" }) -TempQueryDoId $null

        $Written = @($script:ConfigWrites | Where-Object { $_.Property -eq "CurrentSqlQuery" })
        $Written.Count | Should -BeGreaterThan 0
        $Written.Value | Should -Contain 777
    }

    It "does not throw when the response is an ErrorRecord" {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("boom"), "OmadaFailure",
            [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

        { Complete-ExecuteQueryResult -QueryResult $ErrorRecord -SaveResult ([pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }) -TempQueryDoId $null } | Should -Not -Throw
        $Script:MainForm.Elements.ButtonExecuteQuery.IsEnabled | Should -BeTrue
    }
}
