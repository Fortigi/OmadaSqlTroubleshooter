[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'WebViewInstalled', Justification = 'The variable is used, but script analyzer does not recognize it')]
PARAM()

if (-not (Test-Path "$PSScriptRoot\Lib\Functions\Public" -PathType Container)) {
    $Public = @(Get-ChildItem "$PsscriptRoot\Lib\Functions\Functions.ps1")
}
else {
    $Public = @(Get-ChildItem -Path $PSScriptRoot\Lib\Functions\Public\*.ps1 -Recurse)
}
if (-not(Test-Path "$PSScriptRoot\Lib\Functions\Private" -PathType Container)) {
    $Private = @()
}
else {
    $Private = @(Get-ChildItem -Path $PSScriptRoot\Lib\Functions\Private\*.ps1 -Recurse)
}
Foreach ($Import in @($Public + $Private)) {
    try {
        . $Import.FullName
    }
    catch {
        "Failed to import function {0}: {1}" -f $($Import.FullName), $_ | Write-Error -ErrorAction "Stop"
    }
}

$WebViewInstalled = $false
(Join-Path $env:ProgramFiles -ChildPath "Microsoft\EdgeWebView"), (Join-Path ${env:ProgramFiles(x86)} -ChildPath "Microsoft\EdgeWebView") | ForEach-Object {
    if (Test-Path $_) {
        (Get-ChildItem $_ -Filter *.exe -Recurse | Where-Object { $_.Name -eq "msedgewebview2.exe" }) | ForEach-Object {
            "A webview installation found at '{0}'" -f (Split-Path $_) | Write-Verbose
            $WebViewInstalled = $true
        }
    }
}
if (!$WebViewInstalled -and !(Test-Path (Join-Path $LocalAppDataPath -ChildPath "bin\Webview2Runtime\.downloadWebViewRunTime") -PathType Leaf) -and !(Test-Path (Join-Path $LocalAppDataPath -ChildPath "bin\Webview2Runtime\msedgewebview2.exe") -PathType Leaf)) {
    $Message = "Copy Webview2 RunTime files here because the Webview2 RunTime does not seem to be present at your system. You can download it from: https://developer.microsoft.com/en-us/microsoft-edge/webview2?form=MA13LH#download-section" | Write-Warning
    $Message | Out-File (Join-Path $LocalAppDataPath -ChildPath "bin\Webview2Runtime\.downloadWebViewRunTime") -Force -Encoding utf8
}
else { try { Get-Item (Join-Path $LocalAppDataPath -ChildPath "bin\Webview2Runtime\.downloadWebViewRunTime") | Remove-Item -Force -Confirm:$false }catch {} }

#Check shortcuts
Test-Shortcut

# Export all the functions
Export-ModuleMember -Function "Invoke-OmadaSqlTroubleshooter" -Alias *
