#Requires -Version 7.0

BeforeAll {
    . (Join-Path $PSScriptRoot "AdHocQueryDraftStore.Shared.ps1")
}

Describe 'Write-AdHocQueryDraftStore' -Tag 'Unit' {
    BeforeEach {
        $script:Store = Join-Path $TestDrive ("{0}.json" -f [guid]::NewGuid())
    }

    It 'Should write a versioned store' {
        Write-AdHocQueryDraftStore -Path $script:Store -Draft @([PSCustomObject]@{ TabId = "a"; Text = "SELECT 1" })

        $Store = Get-Content -LiteralPath $script:Store -Raw | ConvertFrom-Json
        $Store.Version | Should -Be 1
        @($Store.Drafts).Count | Should -Be 1
    }

    It 'Should create the folder the store goes in' {
        $Nested = Join-Path $TestDrive ([System.IO.Path]::Combine([guid]::NewGuid().ToString(), "config", "drafts.json"))

        Write-AdHocQueryDraftStore -Path $Nested -Draft @([PSCustomObject]@{ TabId = "a"; Text = "SELECT 1" })

        Test-Path -LiteralPath $Nested -PathType Leaf | Should -BeTrue
    }

    It 'Should write into a folder that already exists' {
        $Folder = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $Folder -ItemType Directory | Out-Null
        $Path = Join-Path $Folder "drafts.json"

        Write-AdHocQueryDraftStore -Path $Path -Draft @([PSCustomObject]@{ TabId = "a"; Text = "SELECT 1" })

        (Get-AdHocQueryDraft -Path $Path).TabId | Should -Be "a"
    }

    It 'Should remove the store rather than write an empty one' -ForEach @(
        @{ Case = 'no drafts'; Draft = @() }
        @{ Case = 'only nulls'; Draft = @($null) }
    ) {
        Set-Content -LiteralPath $script:Store -Value "{}"

        Write-AdHocQueryDraftStore -Path $script:Store -Draft $Draft

        Test-Path -LiteralPath $script:Store | Should -BeFalse
    }

    It 'Should not create a store for no drafts' {
        Write-AdHocQueryDraftStore -Path $script:Store -Draft @()

        Test-Path -LiteralPath $script:Store | Should -BeFalse
    }

    It 'Should replace the store as a whole' {
        Write-AdHocQueryDraftStore -Path $script:Store -Draft @([PSCustomObject]@{ TabId = "a"; Text = "1" }, [PSCustomObject]@{ TabId = "b"; Text = "2" })
        Write-AdHocQueryDraftStore -Path $script:Store -Draft @([PSCustomObject]@{ TabId = "c"; Text = "3" })

        @(Get-AdHocQueryDraft -Path $script:Store | ForEach-Object { $_.TabId }) | Should -Be @("c")
        Test-Path -LiteralPath ("{0}.tmp" -f $script:Store) | Should -BeFalse
    }
}
