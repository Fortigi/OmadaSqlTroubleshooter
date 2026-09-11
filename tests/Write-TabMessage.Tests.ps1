# The Messages pane is what replaced the modal dialog for query failures (issue #93). The two things
# worth proving about it are that messages accumulate within an execute and clear at the start of the
# next, and that two tabs failing at the same time keep their output apart - the latter being an
# explicit acceptance criterion, and the failure mode background execution (issue #40) made possible.
#
# Headless: plain objects stand in for the WPF elements, because CI's pwsh cannot resolve
# System.Windows.* at all.

BeforeAll {
    $PrivatePath = Join-Path $PSScriptRoot -ChildPath "..\src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Write-TabMessage.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)][string]$Message, $LogType, $ErrorObject) process { } }

    function script:New-MessageTabStub {
        param([string]$Id)
        return [pscustomobject]@{
            Id            = $Id
            QueryMessages = [System.Collections.Generic.List[string]]::new()
            Elements      = @{
                TextBoxQueryMessages  = [pscustomobject]@{ Text = "" }
                TabControlQueryOutput = [pscustomobject]@{ SelectedIndex = 0 }
            }
        }
    }

    function Get-ActiveTabSession { return $Script:ActiveStub }
}

Describe "Add-TabMessage" {
    BeforeEach {
        $Script:TabA = New-MessageTabStub -Id "tab-A"
        $Script:ActiveStub = $Script:TabA
    }

    It "accumulates messages within one execute rather than replacing them" {
        Add-TabMessage -TabSession $Script:TabA -Text "Rows read: 12"
        Add-TabMessage -TabSession $Script:TabA -Text "Completion time: 00:00:01.2"

        $Script:TabA.QueryMessages.Count | Should -Be 2
        $Script:TabA.Elements.TextBoxQueryMessages.Text | Should -Match "Rows read: 12"
        $Script:TabA.Elements.TextBoxQueryMessages.Text | Should -Match "Completion time: 00:00:01.2"
    }

    It "renders the pane from the list, so the two cannot drift" {
        Add-TabMessage -TabSession $Script:TabA -Text "first"
        Add-TabMessage -TabSession $Script:TabA -Text "second"

        $Script:TabA.Elements.TextBoxQueryMessages.Text | Should -Be ($Script:TabA.QueryMessages -join "`r`n")
    }

    It "brings the pane to the front when asked" {
        Add-TabMessage -TabSession $Script:TabA -Text "The query pipeline failed at step 'Execute'" -Focus

        $Script:TabA.Elements.TabControlQueryOutput.SelectedIndex | Should -Be 1
    }

    It "leaves Results selected when not asked" {
        # On success the user stays on their data - the other half of the same acceptance criterion.
        Add-TabMessage -TabSession $Script:TabA -Text "Rows read: 12"

        $Script:TabA.Elements.TabControlQueryOutput.SelectedIndex | Should -Be 0
    }

    It "defaults to the active tab" {
        Add-TabMessage -Text "Rows read: 0"

        $Script:TabA.QueryMessages | Should -Contain "Rows read: 0"
    }

    It "does not throw when there is no tab at all" {
        $Script:ActiveStub = $null

        { Add-TabMessage -Text "orphaned" } | Should -Not -Throw
    }

    It "records the message even for a tab whose elements are not built yet" {
        # A deferred tab has no form until Complete-TabMaterialization. The message must still survive:
        # the list is the source of truth and the pane re-renders from it.
        #
        # Plain variables, not $Private: - that scope modifier hides a variable from CHILD scopes, so
        # the name is $null inside the { } handed to Should -Not -Throw, and the call under test would
        # silently receive no tab at all and assert nothing.
        $Bare = [pscustomobject]@{ Id = "tab-C"; QueryMessages = [System.Collections.Generic.List[string]]::new(); Elements = $null }

        { Add-TabMessage -TabSession $Bare -Text "held" } | Should -Not -Throw
        $Bare.QueryMessages | Should -Contain "held"
    }

    It "creates the list for a tab that somehow has none" {
        $Legacy = [pscustomobject]@{ Id = "tab-D"; QueryMessages = $null; Elements = $null }

        Add-TabMessage -TabSession $Legacy -Text "late"

        $Legacy.QueryMessages | Should -Contain "late"
    }
}

Describe "Clear-TabMessage" {
    BeforeEach {
        $Script:TabA = New-MessageTabStub -Id "tab-A"
        $Script:ActiveStub = $Script:TabA
    }

    It "empties the pane at the start of the next execute" {
        Add-TabMessage -TabSession $Script:TabA -Text "Rows read: 12"
        Add-TabMessage -TabSession $Script:TabA -Text "Completion time: 00:00:01.2"

        Clear-TabMessage -TabSession $Script:TabA

        $Script:TabA.QueryMessages.Count | Should -Be 0
        $Script:TabA.Elements.TextBoxQueryMessages.Text | Should -BeNullOrEmpty
    }

    It "returns the selection to Results" {
        # Without this, a tab left on Messages by a previous failure would keep the user staring at the
        # pane while the new query produced rows they could not see.
        Add-TabMessage -TabSession $Script:TabA -Text "it failed" -Focus
        $Script:TabA.Elements.TabControlQueryOutput.SelectedIndex | Should -Be 1

        Clear-TabMessage -TabSession $Script:TabA

        $Script:TabA.Elements.TabControlQueryOutput.SelectedIndex | Should -Be 0
    }

    It "does not throw when there is no tab at all" {
        $Script:ActiveStub = $null

        { Clear-TabMessage } | Should -Not -Throw
    }
}

Describe "Write-TabExecuteSummary" {
    BeforeEach {
        $Script:TabA = New-MessageTabStub -Id "tab-A"
        $Script:ActiveStub = $Script:TabA
    }

    It "records rows read and completion time" {
        Write-TabExecuteSummary -TabSession $Script:TabA -RowsRead 1204 -Elapsed "00:00:02.4100000"

        # The group separator is whatever the machine's culture uses - "1,204" here, "1.204" on the
        # Dutch and German machines this is actually developed on - so the assertion matches either
        # rather than pinning the suite to one locale. The count is what matters, not the comma.
        ($Script:TabA.QueryMessages -join " ") | Should -Match 'Rows read: 1[.,]204'
        $Script:TabA.QueryMessages | Should -Contain "Completion time: 00:00:02.4100000"
    }

    It "records them for a failed execute too, which is the point" {
        # Issue #93 asks for both numbers on EVERY execute, and that is what separates "the query
        # returned nothing" from "the query failed" - the ambiguity issue #44 describes. A failure
        # that read no rows still gets a summary rather than silence.
        Write-TabExecuteSummary -TabSession $Script:TabA -RowsRead 0 -Elapsed "00:00:00.8000000"

        $Script:TabA.QueryMessages | Should -Contain "Rows read: 0"
        $Script:TabA.QueryMessages | Should -Contain "Completion time: 00:00:00.8000000"
    }

    It "does not steal focus from Results" {
        Write-TabExecuteSummary -TabSession $Script:TabA -RowsRead 3 -Elapsed "00:00:00.1000000"

        $Script:TabA.Elements.TabControlQueryOutput.SelectedIndex | Should -Be 0
    }
}

Describe "Two tabs failing concurrently" {
    # The acceptance criterion that names a test explicitly. Background execution means both
    # completions can land while the user is looking at a third thing entirely, and the tab the code
    # is acting FOR is not the tab on SCREEN - so anything reached through $Script:MainForm.Elements
    # would cross the streams. Reaching through the tab session cannot.
    BeforeEach {
        $Script:TabA = New-MessageTabStub -Id "tab-A"
        $Script:TabB = New-MessageTabStub -Id "tab-B"
        $Script:ActiveStub = $null
    }

    It "keeps each tab's messages to itself" {
        Clear-TabMessage -TabSession $Script:TabA
        Clear-TabMessage -TabSession $Script:TabB

        Add-TabMessage -TabSession $Script:TabA -Text "Tab A: invalid column name 'Idenity'" -Focus
        Add-TabMessage -TabSession $Script:TabB -Text "Tab B: timeout expired" -Focus

        Write-TabExecuteSummary -TabSession $Script:TabA -RowsRead 0 -Elapsed "00:00:03.0000000"
        Write-TabExecuteSummary -TabSession $Script:TabB -RowsRead 0 -Elapsed "00:00:30.0000000"

        $Script:TabA.Elements.TextBoxQueryMessages.Text | Should -Match "invalid column name"
        $Script:TabA.Elements.TextBoxQueryMessages.Text | Should -Not -Match "timeout expired"
        $Script:TabA.Elements.TextBoxQueryMessages.Text | Should -Match "00:00:03"

        $Script:TabB.Elements.TextBoxQueryMessages.Text | Should -Match "timeout expired"
        $Script:TabB.Elements.TextBoxQueryMessages.Text | Should -Not -Match "invalid column name"
        $Script:TabB.Elements.TextBoxQueryMessages.Text | Should -Match "00:00:30"
    }

    It "clearing one tab's pane leaves the other's alone" {
        # The next execute on tab A must not wipe the failure tab B is still showing.
        Add-TabMessage -TabSession $Script:TabA -Text "Tab A failed"
        Add-TabMessage -TabSession $Script:TabB -Text "Tab B failed"

        Clear-TabMessage -TabSession $Script:TabA

        $Script:TabA.QueryMessages.Count | Should -Be 0
        $Script:TabB.QueryMessages | Should -Contain "Tab B failed"
    }

    It "focusing one tab's pane does not move the other's selection" {
        Add-TabMessage -TabSession $Script:TabA -Text "Tab A failed" -Focus

        $Script:TabA.Elements.TabControlQueryOutput.SelectedIndex | Should -Be 1
        $Script:TabB.Elements.TabControlQueryOutput.SelectedIndex | Should -Be 0
    }
}
