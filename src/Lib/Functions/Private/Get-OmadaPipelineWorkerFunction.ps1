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
        # Trimmed, because IsNullOrWhiteSpace accepts " Invoke-X " and & " Invoke-X " does not find
        # it. More to the point, Test-OmadaPipelineWorkerChain matches this name against a file name,
        # and a comparison is only as sound as the normalisation behind it.
        return ([string]$PipelineContext.PipelineFunction).Trim()
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

    if ($null -ne $PipelineContext -and $null -ne $PipelineContext.PipelineFiles) {
        # Empty and whitespace entries dropped: Join-Path with a null ChildPath throws, and the
        # pre-flight check that would have caught a missing file instead falls over on the way to it.
        $Private:Files = @($PipelineContext.PipelineFiles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { ([string]$_).Trim() })
        if ($Private:Files.Count -gt 0) {
            return $Private:Files
        }
    }

    return @("New-OmadaQueryRequest.ps1", "Invoke-OmadaExecutePipeline.ps1")
}

function Test-OmadaPipelineWorkerChain {
    <#
    .SYNOPSIS
    Whether the named entry point is actually defined by one of the named files.

    .DESCRIPTION
    The gap this closes: the pre-flight check in Start-OmadaBackgroundRequest confirms the FILES
    exist, and nothing confirms the FUNCTION is in them. A typo in PipelineFunction therefore passed
    every check and died inside the worker - turning what the whole fallback design promises to be a
    clean "run it inline instead" into a background job that fails.

    Unavailability of any kind has to mean the same thing here, which is why this is a pre-flight
    test rather than a runtime error: slower is better than broken.

    Matched by the repository's one-public-function-per-file convention, so
    Invoke-OmadaViewLookupPipeline must be accompanied by Invoke-OmadaViewLookupPipeline.ps1. The
    chain's other files - request builders and the like - are not the entry point and are not
    matched.

    .PARAMETER PipelineFunction
    The resolved entry point name.

    .PARAMETER PipelineFiles
    The resolved file list.

    .OUTPUTS
    [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$PipelineFunction,

        [string[]]$PipelineFiles
    )

    if ([string]::IsNullOrWhiteSpace($PipelineFunction) -or $null -eq $PipelineFiles) {
        return $false
    }

    $Private:Expected = "{0}.ps1" -f $PipelineFunction.Trim()

    return @($PipelineFiles | Where-Object { $_ -eq $Private:Expected }).Count -gt 0
}
