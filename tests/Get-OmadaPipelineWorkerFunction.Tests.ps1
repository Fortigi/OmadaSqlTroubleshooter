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

Describe "Get-OmadaWorkerRuntimeFile" {
    # The list the BUILD ships. A worker runspace imports OmadaWeb.PS and nothing else, so it cannot
    # see anything merged into the psm1 and loads these from disk by path. The package shipped
    # without them once: every dispatch failed its pre-flight check and fell back to the UI thread,
    # so background execution, the Cancel button and the live elapsed time were all absent from the
    # released module while every test passed - because dev and E2E both run from src/.
    It "includes the core, which every worker dot-sources whatever chain it runs" {
        Get-OmadaWorkerRuntimeFile | Should -Contain "Invoke-OmadaRequestCore.ps1"
    }

    It "includes every file of <_>" -ForEach @("Invoke-OmadaExecutePipeline", "Invoke-OmadaViewLookupPipeline") {
        $Private:Shipped = Get-OmadaWorkerRuntimeFile

        foreach ($Private:File in (Get-OmadaPipelineWorkerFile -PipelineContext @{ PipelineFunction = $_; PipelineFiles = $null })) {
            $Private:Shipped | Should -Contain $Private:File
        }
    }

    It "covers the view lookup's chain, which is the one the default list does not" {
        # The regression guard with teeth: the default chain would ship anyway. A SECOND chain is
        # what a hand-maintained list forgets.
        Get-OmadaWorkerRuntimeFile | Should -Contain "Invoke-OmadaViewLookupPipeline.ps1"
        Get-OmadaWorkerRuntimeFile | Should -Contain "New-OmadaPagingRequest.ps1"
    }

    It "lists each file once, however many chains name it" {
        $Private:Shipped = @(Get-OmadaWorkerRuntimeFile)

        ($Private:Shipped | Select-Object -Unique).Count | Should -Be $Private:Shipped.Count
    }

    It "names only files that exist in source" {
        foreach ($Private:File in (Get-OmadaWorkerRuntimeFile)) {
            Join-Path $script:PrivatePath $Private:File | Should -Exist
        }
    }

    It "is where the default chain's file list comes from, rather than a second copy" {
        # If these ever diverge, the dispatch loads one thing and the build ships another.
        Get-OmadaPipelineWorkerFile -PipelineContext $null | Should -Be $Script:OmadaWorkerChainFile["Invoke-OmadaExecutePipeline"]
    }
}

Describe "The build ships what a worker loads" {
    # Asserted on the build script, because the build has not run when this suite does - the psake
    # chain is Analyze, Test, Build. The real guard is the post-condition INSIDE the build, which
    # fails it outright; this makes sure that guard, and the copy it guards, still exist.
    BeforeAll {
        $script:BuildScript = Get-Content -Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "build\psakeBuild.ps1") -Raw
    }

    It "copies the worker's files into the package" {
        $script:BuildScript | Should -Match 'Copy background worker functions'
        $script:BuildScript | Should -Match 'Get-OmadaWorkerRuntimeFile'
    }

    It "takes the list from the module rather than repeating it in the build" {
        # A hand-maintained copy here is the thing that silently stops matching the code.
        $script:BuildScript | Should -Match 'Get-OmadaPipelineWorkerFunction\.ps1'
        $script:BuildScript | Should -Not -Match 'Invoke-OmadaViewLookupPipeline\.ps1"'
    }

    It "fails the build when a file did not make it into the package" {
        # Not a warning: a package missing these starts perfectly well and quietly does less, which
        # is exactly how this shipped unnoticed.
        $script:BuildScript | Should -Match 'was not copied to .+The published module would run every query on the UI thread'
    }

    It "copies after the functions merge, which empties that folder" {
        # Ordering is load-bearing: the merge deletes lib\functions recursively before writing, so a
        # copy placed earlier is deleted again and the bug comes back looking like a build flake.
        $Private:MergeAt = $script:BuildScript.IndexOf('$LibSource = "functions"')
        $Private:CopyAt = $script:BuildScript.IndexOf('Copy background worker functions')

        $Private:MergeAt | Should -BeGreaterThan 0
        $Private:CopyAt | Should -BeGreaterThan $Private:MergeAt
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
