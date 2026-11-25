#Requires -Version 7.0

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . ([System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private", "Set-TabQueryClean.ps1"))

    $script:Headers = 0
    function Update-TabHeaderTitle { param($TabSession) $script:Headers++ }
}

Describe 'Set-TabQueryClean' -Tag 'Unit' {
    BeforeEach {
        $script:Headers = 0
    }

    It 'Should clear the dirty flag after a query was loaded, and refresh the header' {
        $Tab = [PSCustomObject]@{ IsDirty = $true }

        Set-TabQueryClean -TabSession $Tab

        $Tab.IsDirty | Should -BeFalse
        $script:Headers | Should -Be 1
    }

    It 'Should not refresh the header of a tab that was already clean' {
        $Tab = [PSCustomObject]@{ IsDirty = $false }

        Set-TabQueryClean -TabSession $Tab

        $Tab.IsDirty | Should -BeFalse
        $script:Headers | Should -Be 0
    }

    It 'Should ignore a missing tab' {
        { Set-TabQueryClean -TabSession $null } | Should -Not -Throw
        $script:Headers | Should -Be 0
    }

    It 'Should mark the tab changed when the editor was loaded with a restored older version' {
        $Tab = [PSCustomObject]@{ IsDirty = $false }

        Set-TabQueryClean -TabSession $Tab -Restored

        $Tab.IsDirty | Should -BeTrue
        $script:Headers | Should -Be 1
    }

    It 'Should not refresh the header of a tab that was already changed when a version is restored' {
        $Tab = [PSCustomObject]@{ IsDirty = $true }

        Set-TabQueryClean -TabSession $Tab -Restored

        $Tab.IsDirty | Should -BeTrue
        $script:Headers | Should -Be 0
    }
}
