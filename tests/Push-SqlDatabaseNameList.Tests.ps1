#Requires -Version 7.0
# The push that tells the Monaco editor which names are data connections (issue #158).
#
# Every assertion here is about the PAYLOAD being valid JavaScript, because that is the way this
# function fails: a malformed script does not throw anywhere PowerShell can see it. The WebView
# swallows the syntax error, the editor keeps whatever list it had, and cross-database completion
# quietly stops working.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-JavaScriptLiteral.ps1")
    . (Join-Path $PrivatePath -ChildPath "Resolve-DataConnectionReference.ps1")
    . (Join-Path $PrivatePath -ChildPath "Push-SqlDatabaseNameList.ps1")

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

    $script:OptionList = @("OISES - 1001572", "Reporting - 1001999")

    function Get-DataConnectionOptionText {
        param([switch]$NoRefresh)
        return , @($script:OptionList)
    }

    $script:PushedScripts = [System.Collections.Generic.List[string]]::new()

    function Invoke-ExecuteScriptAsync {
        param($ScriptToExecute, $OnCompletedScriptBlock)
        $script:PushedScripts.Add([string]$ScriptToExecute)
    }

    function script:Get-PushedArgument {
        <#
            Pulls the two arguments out of "setDatabaseNames(<names>, <active>);" so the tests can
            assert on each, and so a malformed call is visible rather than merely odd-looking.
        #>
        param([string]$Script)

        if ($Script -match '^setDatabaseNames\((?<Names>.*),\s*(?<Active>"(?:[^"\\]|\\.)*")\);$') {
            return [PSCustomObject]@{ Names = $Matches.Names.Trim(); Active = $Matches.Active }
        }

        return $null
    }
}

Describe "Push-SqlDatabaseNameList" {
    BeforeEach {
        $script:PushedScripts.Clear()
        $script:OptionList = @("OISES - 1001572", "Reporting - 1001999")
        $Script:AppConfig = [PSCustomObject]@{
            CurrentDataConnection = [PSCustomObject]@{ DoId = "1001572"; FullName = "OISES - 1001572" }
        }
    }

    It "pushes every data connection name" {
        Push-SqlDatabaseNameList

        $Argument = Get-PushedArgument -Script $script:PushedScripts[-1]
        $Argument | Should -Not -BeNullOrEmpty
        ($Argument.Names | ConvertFrom-Json) | Should -Be @("OISES", "Reporting")
    }

    It "names the active connection by its NAME, not its display text" {
        # The editor compares it against what the user typed between brackets, so "OISES - 1001572"
        # would never match.
        Push-SqlDatabaseNameList

        (Get-PushedArgument -Script $script:PushedScripts[-1]).Active | Should -Be '"OISES"'
    }

    It "reports the DoId it was given rather than the tab's current one" {
        Push-SqlDatabaseNameList -ActiveDataConnectionDoId "1001999"

        (Get-PushedArgument -Script $script:PushedScripts[-1]).Active | Should -Be '"Reporting"'
    }

    It "falls back to the tab's current connection when given no DoId" {
        Push-SqlDatabaseNameList -ActiveDataConnectionDoId ""

        (Get-PushedArgument -Script $script:PushedScripts[-1]).Active | Should -Be '"OISES"'
    }

    Context "an empty connection list" {
        # The regression Copilot caught on PR #160, and the reason this file exists. An
        # active-connection schema response can arrive BEFORE the dropdown is populated, so this is
        # reachable rather than theoretical.
        BeforeEach {
            $script:OptionList = @()
        }

        It "pushes a valid empty array, not a missing argument" {
            # Nothing reaches ConvertTo-Json through an empty pipeline, so it returns $null and the
            # payload used to interpolate to "setDatabaseNames(, "");" - a JavaScript syntax error
            # that fails silently in the WebView.
            Push-SqlDatabaseNameList

            $script:PushedScripts[-1] | Should -Not -BeLike "setDatabaseNames(,*"
            $Argument = Get-PushedArgument -Script $script:PushedScripts[-1]
            $Argument | Should -Not -BeNullOrEmpty
            $Argument.Names | Should -Be "[]"
        }

        It "does not wrap the empty array, which -InputObject would" {
            # -InputObject @() serialises to "[[]]"; asserted on the parsed argument rather than with
            # a wildcard, because "[" is itself a wildcard metacharacter in -BeLike.
            Push-SqlDatabaseNameList

            (Get-PushedArgument -Script $script:PushedScripts[-1]).Names | Should -Not -Be "[[]]"
        }

        It "still pushes an active name argument" {
            Push-SqlDatabaseNameList

            (Get-PushedArgument -Script $script:PushedScripts[-1]).Active | Should -Be '""'
        }
    }

    It "serialises a single connection as a JSON array" {
        # setDatabaseNames iterates its first argument; a lone string would be walked per character.
        $script:OptionList = @("OISES - 1001572")

        Push-SqlDatabaseNameList

        (Get-PushedArgument -Script $script:PushedScripts[-1]).Names | Should -Be '["OISES"]'
    }

    It "escapes a name that would otherwise break the literal" {
        $script:OptionList = @('Odd"Name - 1001572')

        Push-SqlDatabaseNameList

        # Through ConvertTo-Json / ConvertTo-JavaScriptLiteral, so the quote cannot end the literal
        # early and run the remainder as script.
        $script:PushedScripts[-1] | Should -BeLike '*\"*'
        { Get-PushedArgument -Script $script:PushedScripts[-1] } | Should -Not -Throw
    }

    It "does not throw when the connection list cannot be read" {
        function Get-DataConnectionOptionText { param([switch]$NoRefresh) throw "no connection list" }

        { Push-SqlDatabaseNameList } | Should -Not -Throw
        $script:PushedScripts.Count | Should -Be 0
    }
}
