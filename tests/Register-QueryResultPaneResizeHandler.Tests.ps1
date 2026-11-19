#Requires -Version 7.0
# Sizing the result grids again when the Results pane changes height. The headless half: which tab a
# resized pane belongs to, and that the handler is added once per pane. Whether a real resize ends
# with the grid fitting the pane is measured in QueryResultStackLayout.Sta.Tests.ps1.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Update-QueryResultStackLayout.ps1")

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

    # A pane stand-in that counts its SizeChanged subscriptions.
    function script:New-TestPane {
        $Private:Pane = [pscustomobject]@{ Tag = $null; Subscribed = 0 }
        $Private:Pane | Add-Member -MemberType ScriptMethod -Name Add_SizeChanged -Value { param($Handler) $this.Subscribed++ }
        return $Private:Pane
    }

    function script:New-TestTab {
        param([string]$Id, $Pane)
        return [pscustomobject]@{ Id = $Id; Elements = @{ ScrollViewerQueryResults = $Pane } }
    }
}

Describe 'Register-QueryResultPaneResizeHandler' -Tag 'Unit' {

    It 'subscribes to the pane once, however often it is called' {
        $Private:Pane = New-TestPane
        $Private:Tab = New-TestTab -Id "A" -Pane $Private:Pane

        Register-QueryResultPaneResizeHandler -TabSession $Private:Tab
        Register-QueryResultPaneResizeHandler -TabSession $Private:Tab

        $Private:Pane.Subscribed | Should -Be 1
        $Private:Pane.Tag | Should -Be "QueryResultPaneResize"
    }

    It 'does nothing for a tab without a Results pane' {
        { Register-QueryResultPaneResizeHandler -TabSession (New-TestTab -Id "A" -Pane $null) } | Should -Not -Throw
    }
}

Describe 'Invoke-QueryResultPaneResize' -Tag 'Unit' {

    BeforeEach {
        $script:Sized = [System.Collections.Generic.List[string]]::new()
        Mock Update-QueryResultStackLayout { $script:Sized.Add($TabSession.Id) }
    }

    It 'sizes the tab that owns the resized pane, not another one' {
        $Private:PaneA = New-TestPane
        $Private:PaneB = New-TestPane
        $Script:Tabs = @((New-TestTab -Id "A" -Pane $Private:PaneA), (New-TestTab -Id "B" -Pane $Private:PaneB))

        Invoke-QueryResultPaneResize -ScrollViewer $Private:PaneB

        @($script:Sized) | Should -Be @("B")
    }

    It 'does nothing for a pane no tab owns, such as one of a closed tab' {
        $Script:Tabs = @(New-TestTab -Id "A" -Pane (New-TestPane))

        Invoke-QueryResultPaneResize -ScrollViewer (New-TestPane)

        $script:Sized.Count | Should -Be 0
    }

    It 'logs rather than throws when the sizing pass fails' {
        $Private:Pane = New-TestPane
        $Script:Tabs = @(New-TestTab -Id "A" -Pane $Private:Pane)
        Mock Update-QueryResultStackLayout { throw "layout failed" }

        { Invoke-QueryResultPaneResize -ScrollViewer $Private:Pane } | Should -Not -Throw
    }
}
