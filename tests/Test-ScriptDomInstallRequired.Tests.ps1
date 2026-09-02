#Requires -Version 7.0
# The ScriptDom assembly lives in a user-writable folder, so the pin that was verified at download
# time says nothing about the bytes that are there now. Raised in review of PR #74: the stamp
# recorded a SHA-256 that nothing read back, which let a swapped DLL survive a verified install
# indefinitely. These tests are what keeps that check in place.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Get-FileSha256.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-ScriptDomStamp.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-ScriptDomStamp.ps1")
    . (Join-Path $PrivatePath -ChildPath "Test-ScriptDomInstallRequired.ps1")

    # The pinned version comes from the real lock file, so a bump cannot leave these tests asserting
    # against a version the module no longer installs.
    $Script:Lock = Import-PowerShellDataFile -Path (Join-Path $ParentPath -ChildPath "src\DependencyLock.psd1")
    $Script:PinnedVersion = @($Script:Lock.Artifacts | Where-Object { $_.Id -eq "Microsoft.SqlServer.TransactSql.ScriptDom" })[0].Version

    function Get-LockedArtifact {
        param([string]$Id)
        return @{ Id = $Id; Version = $Script:PinnedVersion }
    }

    function New-InstalledScriptDom {
        <#
            Lays out a Bin folder holding a stand-in "assembly" and the stamp Install-ScriptDom would
            have written for it. The stamp is produced by the real Write-ScriptDomStamp, so the two
            halves of this contract cannot drift apart in a test that still passes.
        #>
        param([string]$Content = "not really an assembly, but the hash does not care")

        $BinFolder = Join-Path ([System.IO.Path]::GetTempPath()) ("ScriptDomStamp_{0}" -f [guid]::NewGuid().ToString("N"))
        New-Item -Path $BinFolder -ItemType Directory -Force | Out-Null

        $Script:ScriptDomPath = Join-Path $BinFolder "Microsoft.SqlServer.TransactSql.ScriptDom.dll"
        $Script:ScriptDomStampPath = Join-Path $BinFolder "ScriptDom.pin"

        Set-Content -Path $Script:ScriptDomPath -Value $Content -NoNewline -Encoding UTF8
        Write-ScriptDomStamp

        return $BinFolder
    }
}

Describe 'Test-ScriptDomInstallRequired' -Tag 'Unit' {

    BeforeEach {
        $Script:BinFolder = $null
    }

    AfterEach {
        if (![string]::IsNullOrWhiteSpace($Script:BinFolder) -and (Test-Path $Script:BinFolder)) {
            Remove-Item -Path $Script:BinFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'A freshly installed assembly' {
        It 'Should not need reinstalling' {
            $Script:BinFolder = New-InstalledScriptDom

            Test-ScriptDomInstallRequired | Should -BeFalse
        }
    }

    Context 'A tampered assembly' {
        It 'Should need reinstalling when the bytes no longer match the stamp' {
            # The whole point: Bin is user-writable, so an assembly can be replaced after a verified
            # install without the stamp changing. Version alone would have said "fine".
            $Script:BinFolder = New-InstalledScriptDom
            Set-Content -Path $Script:ScriptDomPath -Value "swapped after the verified install" -NoNewline -Encoding UTF8

            Test-ScriptDomInstallRequired | Should -BeTrue
        }

        It 'Should still record a version that matches the pin, so only the hash can catch this' {
            $Script:BinFolder = New-InstalledScriptDom
            Set-Content -Path $Script:ScriptDomPath -Value "swapped after the verified install" -NoNewline -Encoding UTF8

            (Get-ScriptDomStamp).Version | Should -Be $Script:PinnedVersion -Because "a version check alone would pass here"
        }
    }

    Context 'A missing or unusable installation' {
        It 'Should need reinstalling when the assembly is gone' {
            $Script:BinFolder = New-InstalledScriptDom
            Remove-Item -Path $Script:ScriptDomPath -Force

            Test-ScriptDomInstallRequired | Should -BeTrue
        }

        It 'Should need reinstalling when there is no stamp' {
            $Script:BinFolder = New-InstalledScriptDom
            Remove-Item -Path $Script:ScriptDomStampPath -Force

            Test-ScriptDomInstallRequired | Should -BeTrue
        }

        It 'Should need reinstalling when the stamp records <Label>' -ForEach @(
            @{ Label = 'no hash'; Stamp = "@{`r`n    Version = `"999.0.0`"`r`n}" }
            @{ Label = 'no version'; Stamp = "@{`r`n    Sha256 = `"deadbeef`"`r`n}" }
            @{ Label = 'nothing parseable'; Stamp = "this is not a data file {{{" }
        ) {
            $Script:BinFolder = New-InstalledScriptDom
            Set-Content -Path $Script:ScriptDomStampPath -Value $Stamp -Encoding UTF8

            Test-ScriptDomInstallRequired | Should -BeTrue
        }

        It 'Should never throw for an unusable stamp, whatever is in it' {
            $Script:BinFolder = New-InstalledScriptDom
            Set-Content -Path $Script:ScriptDomStampPath -Value "@{ Version = `$(Get-Date) }" -Encoding UTF8

            # SafeGetValue refuses to evaluate a subexpression, so this is unreadable rather than
            # executable - which is the point of parsing the stamp instead of dot-sourcing it.
            { Test-ScriptDomInstallRequired } | Should -Not -Throw
            Test-ScriptDomInstallRequired | Should -BeTrue
        }
    }

    Context 'A pin that has moved' {
        It 'Should need reinstalling when the pin moved <Direction>' -ForEach @(
            @{ Direction = 'forward'; Stamped = '1.0.0' }
            @{ Direction = 'backward'; Stamped = '99999.0.0' }
        ) {
            # -ne, not -lt: a rollback after a bad bump is exactly when this must take effect, and a
            # "is the installed one older?" test would leave the newer, unverified assembly in use.
            $Script:BinFolder = New-InstalledScriptDom
            $Stamp = Get-Content -Path $Script:ScriptDomStampPath -Raw
            Set-Content -Path $Script:ScriptDomStampPath -Value ($Stamp -replace [regex]::Escape($Script:PinnedVersion), $Stamped) -Encoding UTF8

            Test-ScriptDomInstallRequired | Should -BeTrue
        }
    }
}
