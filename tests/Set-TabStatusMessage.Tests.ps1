# The status bar's stretchy column is written from two very different places: straight-line UI code
# on the tab the user is looking at, and background completions for a tab that may be off screen
# (issue #40). Issue #93 made that column carry the application's running commentary, which turns
# "which tab did this write to?" from a detail into the whole correctness question - and issue #71 is
# open precisely because an unidentified second writer of this block was never found.
#
# Headless: plain objects stand in for the WPF elements, because CI's pwsh cannot resolve
# System.Windows.* at all.

BeforeAll {
    $PrivatePath = Join-Path $PSScriptRoot -ChildPath "..\src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Set-TabStatusMessage.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)][string]$Message, $LogType, $ErrorObject) process { } }

    function script:New-StatusTabStub {
        param([string]$Id, [bool]$Connected = $false)
        return [pscustomobject]@{
            Id               = $Id
            ConnectionStatus = $Connected
            Elements         = @{
                TextBlockStatusBarMessage = [pscustomobject]@{ Name = "TextBlockStatusBarMessage"; Text = "" }
            }
        }
    }

    function Get-ActiveTabSession { return $Script:ActiveStub }
}

Describe "Set-TabStatusMessage" {
    BeforeEach {
        $Script:TabA = New-StatusTabStub -Id "tab-A"
        $Script:TabB = New-StatusTabStub -Id "tab-B"
        $Script:ActiveStub = $Script:TabA
    }

    It "writes the message to the tab it was given" {
        Set-TabStatusMessage -TabSession $Script:TabB -Message "Executing query..."

        $Script:TabB.Elements.TextBlockStatusBarMessage.Text | Should -Be "Executing query..."
    }

    It "never writes to a tab it was not given" {
        # THE test of this issue's second acceptance criterion. A background query on tab A must not
        # write its state into tab B's status bar, and since the elements are reached through the tab
        # session rather than through $Script:MainForm.Elements - which Set-ActiveTabContext repoints -
        # it cannot, whatever the user switches to while the query is in flight.
        Set-TabStatusMessage -TabSession $Script:TabB -Message "Query completed with errors"

        $Script:TabA.Elements.TextBlockStatusBarMessage.Text | Should -Be ""
    }

    It "falls back to the active tab when none is named" {
        # The default is what the completion poll timer relies on: it steps into the owning tab before
        # invoking a completion, so "the active tab" there IS the tab the work belongs to.
        Set-TabStatusMessage -Message "Connected"

        $Script:TabA.Elements.TextBlockStatusBarMessage.Text | Should -Be "Connected"
        $Script:TabB.Elements.TextBlockStatusBarMessage.Text | Should -Be ""
    }

    It "replaces the previous message rather than appending to it" {
        # The bar carries the LAST state change, not a history - the history is the Messages pane.
        Set-TabStatusMessage -TabSession $Script:TabA -Message "Executing query..."
        Set-TabStatusMessage -TabSession $Script:TabA -Message "Query 'X' executed successfully - see Messages"

        $Script:TabA.Elements.TextBlockStatusBarMessage.Text | Should -Be "Query 'X' executed successfully - see Messages"
    }

    It "does nothing when there is no tab at all" {
        # Startup and shutdown both reach status-bar writers with no tab context.
        $Script:ActiveStub = $null

        { Set-TabStatusMessage -Message "Connecting to Omada..." } | Should -Not -Throw

        $Script:TabA.Elements.TextBlockStatusBarMessage.Text | Should -Be ""
        $Script:TabB.Elements.TextBlockStatusBarMessage.Text | Should -Be ""
    }

    It "does not throw for a tab whose elements are not built yet" {
        # A deferred tab exists before Complete-TabMaterialization gives it a form, and Restore-
        # TabSessions writes to it on the way there.
        #
        # Plain variables, not $Private: - that scope modifier hides a variable from CHILD scopes, so
        # the name would be $null inside the { } handed to Should -Not -Throw and the call under test
        # would fall back to the active tab, proving nothing about the bare one.
        $Bare = [pscustomobject]@{ Id = "tab-C"; Elements = $null }

        { Set-TabStatusMessage -TabSession $Bare -Message "Retrieving data, please wait..." } | Should -Not -Throw
    }

    It "does not take the operation down with it when the element throws" {
        # The status bar describes work; it must never be the reason the work fails. The message is
        # already in the log by the time this runs.
        $Hostile = [pscustomobject]@{ Id = "tab-D"; Elements = @{} }
        $Block = [pscustomobject]@{}
        $Block | Add-Member -MemberType ScriptProperty -Name Text -Value { "" } -SecondValue { throw "render failed" }
        $Hostile.Elements.TextBlockStatusBarMessage = $Block

        { Set-TabStatusMessage -TabSession $Hostile -Message "Executing query..." } | Should -Not -Throw

        # And the active tab was not written to as a consolation prize.
        $Script:TabA.Elements.TextBlockStatusBarMessage.Text | Should -Be ""
    }
}

Describe "Reset-TabStatusMessage" {
    BeforeEach {
        $Script:TabA = New-StatusTabStub -Id "tab-A" -Connected $true
        $Script:TabB = New-StatusTabStub -Id "tab-B" -Connected $false
        $Script:ActiveStub = $Script:TabA
    }

    It "puts a connected tab back to Connected once an operation finishes" {
        # Progress messages are transient. Leaving "Queries refreshed" on the bar would mean the one
        # question it has always answered - am I connected? - is answered by something else for as
        # long as the user does not run a query.
        Set-TabStatusMessage -TabSession $Script:TabA -Message "Refreshing queries..."

        Reset-TabStatusMessage -TabSession $Script:TabA

        $Script:TabA.Elements.TextBlockStatusBarMessage.Text | Should -Be "Connected"
    }

    It "puts a disconnected tab back to Disconnected" {
        Set-TabStatusMessage -TabSession $Script:TabB -Message "Opening tab 'Persisted2', please wait..."

        Reset-TabStatusMessage -TabSession $Script:TabB

        $Script:TabB.Elements.TextBlockStatusBarMessage.Text | Should -Be "Disconnected"
    }

    It "reads the tab's own connection flag, not the active tab's" {
        # A refresh finishing on a background tab must report THAT tab's state. $Script:ConnectionStatus
        # follows the active tab, so reading it here would let a connected tab on screen make a
        # disconnected tab in the background claim it was connected too - the split-brain of issue #65.
        $Script:ActiveStub = $Script:TabA

        Reset-TabStatusMessage -TabSession $Script:TabB

        $Script:TabB.Elements.TextBlockStatusBarMessage.Text | Should -Be "Disconnected"
        $Script:TabA.Elements.TextBlockStatusBarMessage.Text | Should -Be ""
    }

    It "defaults to the active tab" {
        Reset-TabStatusMessage

        $Script:TabA.Elements.TextBlockStatusBarMessage.Text | Should -Be "Connected"
    }

    It "does not throw when there is no tab at all" {
        $Script:ActiveStub = $null

        { Reset-TabStatusMessage } | Should -Not -Throw
    }
}
