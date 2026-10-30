#Requires -Version 7.0
# Tests for resolving the ScriptDom parser type (issue #61), and for remembering the assembly's parser
# types rather than enumerating them on every parse (issue #185).

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PSScriptRoot -ChildPath "ScriptDomTestAssembly.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlParserType.ps1")

    $script:ScriptDomPath = Install-ScriptDomForTest -RepositoryRoot $ParentPath
}

Describe 'Get-SqlParserType' -Tag 'Unit' {
    # The assembly's exported types used to be enumerated on every parse - a large share of every
    # debounced validation (issue #185). They are now enumerated once per loaded assembly.

    BeforeEach {
        if ($null -eq $script:ScriptDomPath) {
            Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
        }
    }

    It 'Should resolve the same parser on every call' {
        $Script:SqlParserTypeCache = $null
        $First = Get-SqlParserType

        $First | Should -Not -BeNullOrEmpty
        Get-SqlParserType | Should -Be $First
        Get-SqlParserType -ParserVersion $First.Name | Should -Be $First
    }

    It 'Should remember the enumeration against the assembly it came from' {
        $Script:SqlParserTypeCache = $null
        $null = Get-SqlParserType

        $Assembly = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq "Microsoft.SqlServer.TransactSql.ScriptDom" } | Select-Object -First 1
        [object]::ReferenceEquals($Script:SqlParserTypeCache.Assembly, $Assembly) | Should -BeTrue
    }

    It 'Should not serve a list remembered for a different assembly' {
        # A cache keyed by anything weaker than the assembly itself would keep answering from the
        # first ScriptDom ever seen.
        $Script:SqlParserTypeCache = [PSCustomObject]@{
            Assembly   = [string].Assembly
            ParserType = @([string])
        }

        (Get-SqlParserType).Name | Should -Match '^TSql\d+Parser$'
        $Script:SqlParserTypeCache = $null
    }
}
