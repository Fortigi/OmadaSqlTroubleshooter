# Which dependent chain a background worker runs, and what it must dot-source to run it.
#
# Issue #90, slice A. Start-OmadaBackgroundRequest used to hard-code Invoke-OmadaExecutePipeline as
# THE worker chain. Both answers are needed in three places - the pre-flight file check, the dispatch
# itself, and the E2E harness's stand-in for the worker - and a fourth caller getting a different
# answer from the other three is the failure mode these exist to remove. It happened once already
# during this slice: the harness answered "execute pipeline" while the dispatch answered "view
# lookup", so the view lookup came back with an execute-shaped outcome and the failure looked like a
# defect in the code under test.

function Get-OmadaPipelineWorkerFunction {
    <#
    .SYNOPSIS
    The runspace-safe entry point a worker should call for this pipeline context.

    .PARAMETER PipelineContext
    The context being dispatched, or $null.

    .OUTPUTS
    [string] - the function name. Defaults to the execute pipeline, so a caller that says nothing
    gets exactly the dispatch it got before this became configurable.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [hashtable]$PipelineContext
    )

    if ($null -ne $PipelineContext -and -not [string]::IsNullOrWhiteSpace($PipelineContext.PipelineFunction)) {
        return [string]$PipelineContext.PipelineFunction
    }

    return "Invoke-OmadaExecutePipeline"
}

function Get-OmadaPipelineWorkerFile {
    <#
    .SYNOPSIS
    The files a worker must dot-source to run this pipeline context's chain.

    .PARAMETER PipelineContext
    The context being dispatched, or $null.

    .OUTPUTS
    [string[]] - file names relative to Lib\Functions\Private. Defaults to the execute pipeline's.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()]
        [hashtable]$PipelineContext
    )

    if ($null -ne $PipelineContext -and $null -ne $PipelineContext.PipelineFiles -and @($PipelineContext.PipelineFiles).Count -gt 0) {
        return @($PipelineContext.PipelineFiles)
    }

    return @("New-OmadaQueryRequest.ps1", "Invoke-OmadaExecutePipeline.ps1")
}
