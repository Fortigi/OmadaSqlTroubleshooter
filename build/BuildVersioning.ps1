try {
    $CurrentDate = $(Get-Date)
    $Year = $CurrentDate.Year
    $Month = $CurrentDate.Month
    $Day = $CurrentDate.Day

    "Current date: {0}" -f $CurrentDate | Write-Host
    "Current year: {0}" -f $Year | Write-Host
    "Current month: {0}" -f $Month | Write-Host
    "Current day: {0}" -f $Day | Write-Host
    "Revision: {0}" -f $Env:Revision | Write-Host
    $VersionString = "{0:d4}.{1:d2}.{2:d2}.{3}" -f $Year, $Month, $Day, ($Env:Revision -eq $null ? 0 : $Env:Revision)
$SourceBranchName = "$($env:BUILD_SOURCEBRANCHNAME)"
$SourceBranchName = $SourceBranchName -replace 'refs/heads/', '' -replace '/', ''
    if ("$SourceBranchName" -notin ("master", "main")) {
        $VersionString = "$VersionString-$SourceBranchName"
    }
    Write-Output "Create tag: $($VersionString)"

    "Version: {0}" -f $VersionString | Write-Host
    Write-Host "##vso[task.setvariable variable=buildVersion;isOutput=true]$VersionString"
    Write-Host "##vso[task.setvariable variable=year;isOutput=true]$Year"
}
catch {
    Write-Error "Failed to set build version: $_"
    exit 1
}
