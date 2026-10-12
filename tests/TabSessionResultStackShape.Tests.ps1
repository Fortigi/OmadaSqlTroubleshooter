#Requires -Version 7.0
# The tab session must DECLARE its result-stack state (issue #151).
#
# This exists because of a bug that 2342 passing tests could not see. Set-TabQueryResult writes
# $Target.QueryResults and then $Target.FocusedQueryResultIndex. Assigning a property that a
# [PSCustomObject] does not already have THROWS in PowerShell, so on the real tab session - which
# declared neither - the second assignment threw, Set-TabQueryResult's own catch swallowed it, the
# ItemsControl was never bound, and the status bar reported "0 rows" for a run that had returned nine.
#
# Every headless suite passed throughout, because every fixture declared the two properties itself.
# Only the real constructor did not, and nothing asserted what the real constructor produces. Measured
# in the live app against the mock backend: Set-TabQueryResult ran, received a good outcome
# (rows=9 records=9), set QueryResults to one entry - and FocusedQueryResultIndex came back as an
# EMPTY STRING rather than 0, which is what exposed it.
#
# Asserted against the SOURCE rather than by constructing a session. New-TabSession builds a WPF form,
# a WebView2 and a config graph, none of which loads in a headless lane; what matters here is simply
# that the object literal declares the properties, which is exactly what was missing.

BeforeAll {
    $Script:SourcePath = Join-Path $PSScriptRoot -ChildPath "..\src\Lib\Functions\Private\New-TabSession.ps1"
    $Script:Source = Get-Content -Path $Script:SourcePath -Raw

    $Tokens = $null
    $Errors = $null
    $Script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path $Script:SourcePath).Path, [ref]$Tokens, [ref]$Errors)
    $Script:ParseErrorCount = @($Errors).Count

    # The session object is the [PSCustomObject] literal that carries QueryMessages - the per-tab
    # state this feature's own state sits beside.
    $Script:SessionHashtable = @($Script:Ast.FindAll({
                $args[0] -is [System.Management.Automation.Language.HashtableAst] -and
                @($args[0].KeyValuePairs | ForEach-Object { $_.Item1.Extent.Text }) -contains "QueryMessages"
            }, $true)) | Select-Object -First 1

    $Script:DeclaredKeys = @()
    if ($null -ne $Script:SessionHashtable) {
        $Script:DeclaredKeys = @($Script:SessionHashtable.KeyValuePairs | ForEach-Object { $_.Item1.Extent.Text })
    }
}

Describe "New-TabSession declares the result-stack state" -Tag 'Unit' {

    It "parses, so the assertions below are about real syntax" {
        $Script:ParseErrorCount | Should -Be 0
    }

    It "builds a session object that carries the per-tab Messages list" {
        # The anchor for the rest of this file. If QueryMessages ever moves, these tests are guarding
        # the wrong literal and should fail here rather than silently pass.
        $Script:SessionHashtable | Should -Not -BeNullOrEmpty
        $Script:DeclaredKeys | Should -Contain "QueryMessages"
    }

    It "declares QueryResults, so Set-TabQueryResult can assign it" {
        $Script:DeclaredKeys | Should -Contain "QueryResults"
    }

    It "declares FocusedQueryResultIndex, so the focus assignment cannot throw" {
        # The property whose absence caused the bug. Set-TabQueryResult sets it immediately after
        # QueryResults, so a missing declaration throws AFTER the list is populated - which is why the
        # session looked half-updated and the pane looked empty.
        $Script:DeclaredKeys | Should -Contain "FocusedQueryResultIndex"
    }

    It "initialises the focused index to a number rather than leaving it empty" {
        # An empty string is what the live probe actually observed, and it is indistinguishable from
        # "never set" when read back. Zero is also the agreed default: focus starts on the first
        # result so the commands always have a target.
        $Private:Pair = @($Script:SessionHashtable.KeyValuePairs |
                Where-Object { $_.Item1.Extent.Text -eq "FocusedQueryResultIndex" }) | Select-Object -First 1

        $Private:Pair | Should -Not -BeNullOrEmpty
        $Private:Pair.Item2.Extent.Text.Trim() | Should -Be "0"
    }

    It "initialises QueryResults to a list rather than to null" {
        # Clear-TabQueryResult and Get-FocusedQueryResult both treat it as a collection. A $null here
        # would work by accident - @($null).Count is one - and that is precisely the trap that made
        # an empty pane report a result elsewhere in this feature.
        $Private:Pair = @($Script:SessionHashtable.KeyValuePairs |
                Where-Object { $_.Item1.Extent.Text -eq "QueryResults" }) | Select-Object -First 1

        $Private:Pair.Item2.Extent.Text | Should -Match 'List\[object\]'
    }
}
