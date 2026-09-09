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
