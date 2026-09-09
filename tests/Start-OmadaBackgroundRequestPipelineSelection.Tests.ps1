#Requires -Version 7.0
# Issue #90, slice A. Start-OmadaBackgroundRequest used to hard-code Invoke-OmadaExecutePipeline as
# THE worker chain. Which chain to run is now data on the pipeline context.
#
# WHICH chain gets chosen is covered by Get-OmadaPipelineWorkerFunction.Tests.ps1. What is asserted
# here is that the choice actually reaches the worker: the resolution happens on the UI thread, so
# both answers have to be passed across the runspace boundary, and dropping either one leaves the
# worker calling a null command or dot-sourcing nothing.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $script:DispatchSource = Get-Content -Path (Join-Path $ParentPath "src\Lib\Functions\Private\Start-OmadaBackgroundRequest.ps1") -Raw
}

Describe "The chosen chain reaches the worker" {
    It "resolves both answers on the UI thread" {
        # Rather than inside the worker block, which then needs no knowledge of which chains exist.
        $script:DispatchSource | Should -Match '\$Private:PipelineFunction = Get-OmadaPipelineWorkerFunction'
        $script:DispatchSource | Should -Match '\$Private:PipelineFiles = Get-OmadaPipelineWorkerFile'
    }

    It "passes both across the runspace boundary" {
        $script:DispatchSource | Should -Match 'AddArgument\(\$Private:PipelineFunction\)\.AddArgument\(\$Private:PipelineFiles\)'
    }

    It "receives both in the worker, in the same order" {
        # Positional arguments: a parameter added in the wrong place silently shifts every later one.
        $script:DispatchSource | Should -Match 'param\(\$PrivateFolder, \$RequestParameters, \$PipelineContext, \$TransportScriptPath, \$TransportContext, \$PipelineFunction, \$PipelineFiles\)'
    }

    It "dot-sources whatever files the chain named, not a fixed pair" {
        $script:DispatchSource | Should -Match 'foreach \(\$PipelineFile in \$PipelineFiles\)'
    }

    It "invokes the resolved function rather than a hard-coded one" {
        # The line that would otherwise still say Invoke-OmadaExecutePipeline and make the whole
        # mechanism decorative.
        $script:DispatchSource | Should -Match '& \$PipelineFunction -Context \$PipelineContext'
    }
}

Describe "The view lookup names a chain that exists" {
    It "points at Invoke-OmadaViewLookupPipeline and its files" {
        $Private:Source = Get-Content -Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "src\Lib\Functions\Private\Get-SqlTroubleShooterView.ps1") -Raw

        $Private:Source | Should -Match 'PipelineFunction\s*=\s*"Invoke-OmadaViewLookupPipeline"'
        $Private:Source | Should -Match 'New-OmadaPagingRequest\.ps1'
        $Private:Source | Should -Match 'Invoke-OmadaViewLookupPipeline\.ps1'
    }
}
