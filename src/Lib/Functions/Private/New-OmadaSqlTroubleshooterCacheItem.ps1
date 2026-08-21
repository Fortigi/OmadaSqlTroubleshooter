function New-OmadaSqlTroubleshooterCacheItem {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true)]
        [string]$Scope,
        [parameter(Mandatory = $true)]
        [string]$Artefact,
        [parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Path,
        [parameter(Mandatory = $true)]
        [string]$Protection
    )

    # One report row for Clear-OmadaSqlTroubleshooterCache. Measures what is there without touching
    # it, so -ListOnly and -WhatIf can report the same numbers the removal would act on.
    #
    # No tracer preamble: this command is callable without Invoke-OmadaSqlTroubleshooter having run,
    # so $Script:RunTimeConfig may not exist yet.

    $Exists = -not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path $Path -PathType Container)
    $ItemCount = 0
    $SizeBytes = 0

    if ($Exists) {
        # SilentlyContinue: a browser profile can hold paths longer than MAX_PATH, and failing to
        # measure one file is not a reason to refuse to report the artefact.
        $File = @(Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue)
        $ItemCount = $File.Count
        $SizeBytes = ($File | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $SizeBytes) {
            $SizeBytes = 0
        }
    }

    return [PSCustomObject]@{
        Scope      = $Scope
        Artefact   = $Artefact
        Path       = $Path
        TargetPath = @($Path)
        ItemType   = "Directory"
        Protection = $Protection
        Exists     = $Exists
        ItemCount  = $ItemCount
        SizeBytes  = [long]$SizeBytes
        Removed    = $false
    }
}
