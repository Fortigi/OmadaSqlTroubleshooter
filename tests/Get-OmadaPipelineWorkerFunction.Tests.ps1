#Requires -Version 7.0
# Issue #90, slice A. Which chain a worker runs is now data on the pipeline context. Three places
# need that answer - the pre-flight file check, the dispatch, and the E2E harness's stand-in for the
# worker - and they must not disagree.
#
# They did, once, and it is the reason these functions exist rather than three copies of an `if`:
# the harness answered "execute pipeline" while the dispatch answered "view lookup", so the view
# lookup came back with an execute-shaped outcome, the data connection dropdown was never populated,
# and the E2E failure looked like a defect in the code under test.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $script:PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $script:PrivatePath -ChildPath "Get-OmadaPipelineWorkerFunction.ps1")
}

Describe "Get-OmadaPipelineWorkerFunction" {
    It "defaults to the execute pipeline when there is no context at all" {
        # A single background request, not a chain. #40's callers pass nothing.
        Get-OmadaPipelineWorkerFunction -PipelineContext $null | Should -Be "Invoke-OmadaExecutePipeline"
    }

    It "defaults to the execute pipeline when the context names no chain" {
        Get-OmadaPipelineWorkerFunction -PipelineContext @{ BaseUrl = "https://t" } | Should -Be "Invoke-OmadaExecutePipeline"
    }

    It "returns the chain the context names" {
        Get-OmadaPipelineWorkerFunction -PipelineContext @{ PipelineFunction = "Invoke-OmadaViewLookupPipeline" } | Should -Be "Invoke-OmadaViewLookupPipeline"
    }

    It "ignores an empty or whitespace name rather than dispatching nothing" {
        Get-OmadaPipelineWorkerFunction -PipelineContext @{ PipelineFunction = "" } | Should -Be "Invoke-OmadaExecutePipeline"
        Get-OmadaPipelineWorkerFunction -PipelineContext @{ PipelineFunction = "   " } | Should -Be "Invoke-OmadaExecutePipeline"
    }

    It "trims a padded name, which IsNullOrWhiteSpace accepts but the call operator does not" {
        Get-OmadaPipelineWorkerFunction -PipelineContext @{ PipelineFunction = "  Invoke-OmadaViewLookupPipeline  " } | Should -Be "Invoke-OmadaViewLookupPipeline"
    }
}

Describe "Test-OmadaPipelineWorkerChain" {
    # The gap: the pre-flight check confirms the FILES exist and nothing confirmed the FUNCTION was
    # in them, so a typo passed every check and died inside the worker - turning a clean "run it
    # inline instead" into a background job that fails.
    It "accepts an entry point defined by one of its files" {
        Test-OmadaPipelineWorkerChain -PipelineFunction "Invoke-OmadaViewLookupPipeline" -PipelineFiles @("New-OmadaPagingRequest.ps1", "Invoke-OmadaViewLookupPipeline.ps1") | Should -BeTrue
    }

    It "rejects a typo" {
        Test-OmadaPipelineWorkerChain -PipelineFunction "Invoke-OmadaViewLookupPipelin" -PipelineFiles @("Invoke-OmadaViewLookupPipeline.ps1") | Should -BeFalse
    }

    It "rejects a chain whose entry point file was left out of the list" {
        Test-OmadaPipelineWorkerChain -PipelineFunction "Invoke-OmadaViewLookupPipeline" -PipelineFiles @("New-OmadaPagingRequest.ps1") | Should -BeFalse
    }

    It "accepts the default chain, so #40's dispatch still goes to a worker" {
        # If this ever returns false, every background execute silently runs inline instead.
        Test-OmadaPipelineWorkerChain -PipelineFunction (Get-OmadaPipelineWorkerFunction -PipelineContext $null) -PipelineFiles (Get-OmadaPipelineWorkerFile -PipelineContext $null) | Should -BeTrue
    }

    It "accepts the view lookup's chain as the code actually declares it" {
        # Reads the real declaration rather than a restated copy of it, so a rename that updates the
        # function but not the file list fails here.
        $Private:Source = Get-Content -Path (Join-Path $script:PrivatePath "Get-SqlTroubleShooterView.ps1") -Raw
        $Private:Function = ([regex]::Match($Private:Source, 'PipelineFunction\s*=\s*"([^"]+)"')).Groups[1].Value
        $Private:Files = @([regex]::Matches($Private:Source, '"([A-Za-z-]+\.ps1)"') | ForEach-Object { $_.Groups[1].Value })

        $Private:Function | Should -Not -BeNullOrEmpty
        Test-OmadaPipelineWorkerChain -PipelineFunction $Private:Function -PipelineFiles $Private:Files | Should -BeTrue
    }

    It "says no rather than throwing when there is nothing to check" {
        Test-OmadaPipelineWorkerChain -PipelineFunction "" -PipelineFiles @("x.ps1") | Should -BeFalse
        Test-OmadaPipelineWorkerChain -PipelineFunction "Invoke-X" -PipelineFiles $null | Should -BeFalse
    }
}

Describe "Get-OmadaPipelineWorkerFile" {
    It "defaults to the execute pipeline's files" {
        Get-OmadaPipelineWorkerFile -PipelineContext $null | Should -Be @("New-OmadaQueryRequest.ps1", "Invoke-OmadaExecutePipeline.ps1")
    }

    It "returns the files the context names" {
        $Private:Files = Get-OmadaPipelineWorkerFile -PipelineContext @{ PipelineFiles = @("New-OmadaPagingRequest.ps1", "Invoke-OmadaViewLookupPipeline.ps1") }

        $Private:Files | Should -Be @("New-OmadaPagingRequest.ps1", "Invoke-OmadaViewLookupPipeline.ps1")
    }

    It "ignores an empty list rather than dot-sourcing nothing" {
        Get-OmadaPipelineWorkerFile -PipelineContext @{ PipelineFiles = @() } | Should -Be @("New-OmadaQueryRequest.ps1", "Invoke-OmadaExecutePipeline.ps1")
    }

    It "drops empty entries, which would throw on Join-Path before anything could check them" {
        Get-OmadaPipelineWorkerFile -PipelineContext @{ PipelineFiles = @("Invoke-OmadaViewLookupPipeline.ps1", $null, "  ") } | Should -Be @("Invoke-OmadaViewLookupPipeline.ps1")
    }

    It "falls back to the default when every entry was empty" {
        Get-OmadaPipelineWorkerFile -PipelineContext @{ PipelineFiles = @($null, "") } | Should -Be @("New-OmadaQueryRequest.ps1", "Invoke-OmadaExecutePipeline.ps1")
    }

    It "names files that exist, for <_>" -ForEach @(
        @{ PipelineFunction = "Invoke-OmadaExecutePipeline" },
        @{ PipelineFunction = "Invoke-OmadaViewLookupPipeline"; PipelineFiles = @("New-OmadaPagingRequest.ps1", "Invoke-OmadaViewLookupPipeline.ps1") }
    ) {
        # A named file that does not exist fails inside a worker runspace, where it surfaces as a job
        # that died rather than as a missing file.
        foreach ($Private:File in (Get-OmadaPipelineWorkerFile -PipelineContext $_)) {
            Join-Path $script:PrivatePath $Private:File | Should -Exist
        }
    }
}

Describe "Everyone asks the same question" {
    # The regression that made these functions necessary. Each of the three places must go through
    # them rather than deciding for itself.
    It "<Name> resolves the chain through the shared helper" -ForEach @(
        @{ Name = "the dispatch"; Path = "src\Lib\Functions\Private\Start-OmadaBackgroundRequest.ps1" }
        @{ Name = "the E2E worker stand-in"; Path = "tests\e2e\OmadaMocks.ps1" }
    ) {
        $Private:Source = Get-Content -Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) $Path) -Raw

        $Private:Source | Should -Match 'Get-OmadaPipelineWorkerFunction -PipelineContext'
        $Private:Source | Should -Not -Match '=\s*Invoke-OmadaExecutePipeline -Context'
    }

    It "the pre-flight file check asks for the chain's own files" {
        # It used to require the execute pipeline's two files whatever the chain was, so a second
        # chain's files were never checked - dispatching a worker that then failed on its first line.
        $Private:Source = Get-Content -Path (Join-Path $script:PrivatePath "Start-OmadaBackgroundRequest.ps1") -Raw

        $Private:Source | Should -Match 'RequiredWorkerFiles \+= Get-OmadaPipelineWorkerFile'
    }
}
