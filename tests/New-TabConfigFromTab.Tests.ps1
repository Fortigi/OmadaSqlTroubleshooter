#Requires -Version 7.0
BeforeAll {
    . ([System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private", "New-TabConfigFromTab.ps1"))

    function script:New-SourceTab {
        param([string]$Password = "secret", [bool]$SavePassword = $true)
        return [PSCustomObject]@{
            AppConfig = [PSCustomObject]@{
                BaseUrl               = "https://t"
                LastAuthentication    = "OAuth"
                UserName              = "user"
                EntraApplicationIdUri = "api://app"
                EntraIdTenantId       = "tid"
                MyCreatedQueriesOnly  = $true
                MyUpdatedQueriesOnly  = $false
                IdentityUserName      = "OMADA\user"
                CurrentDataConnection = [PSCustomObject]@{ DoId = 3 }
                ResultOutputMode      = "Text"
                CurrentSqlQuery       = [PSCustomObject]@{ DoId = 99; DisplayName = "Source query" }
            }
            Elements  = [PSCustomObject]@{
                TextBoxPassword      = [PSCustomObject]@{ Password = $Password }
                CheckboxSavePassword = [PSCustomObject]@{ IsChecked = $SavePassword }
            }
        }
    }
}

Describe 'New-TabConfigFromTab' -Tag 'Unit' {
    It 'Should connect like the source tab' {
        $Config = New-TabConfigFromTab -SourceTab (New-SourceTab)

        $Config.BaseUrl | Should -Be "https://t"
        $Config.LastAuthentication | Should -Be "OAuth"
        $Config.UserName | Should -Be "user"
        $Config.EntraApplicationIdUri | Should -Be "api://app"
        $Config.EntraIdTenantId | Should -Be "tid"
        $Config.MyCreatedQueriesOnly | Should -BeTrue
        $Config.MyUpdatedQueriesOnly | Should -BeFalse
        $Config.IdentityUserName | Should -Be "OMADA\user"
        $Config.CurrentDataConnection.DoId | Should -Be 3
        $Config.ResultOutputMode | Should -Be "Text"
        $Config.SavePassword | Should -BeTrue
    }

    It 'Should get a new id' {
        $Config = New-TabConfigFromTab -SourceTab (New-SourceTab)

        { [guid]::Parse($Config.Id) } | Should -Not -Throw
    }

    It 'Should carry the password protected, never as plain text' {
        $Config = New-TabConfigFromTab -SourceTab (New-SourceTab)

        $Config.Password | Should -Not -BeNullOrEmpty
        $Config.Password | Should -Not -Be "secret"
        ($Config.Password | ConvertTo-SecureString | ConvertFrom-SecureString -AsPlainText) | Should -Be "secret"
    }

    It 'Should carry no password when the source has none' {
        (New-TabConfigFromTab -SourceTab (New-SourceTab -Password "")).Password | Should -BeNullOrEmpty
    }

    It 'Should hold a new, unsaved query by default, not the source''s' {
        $Config = New-TabConfigFromTab -SourceTab (New-SourceTab)

        $Config.CurrentSqlQuery.DoId | Should -BeNullOrEmpty
        $Config.DisplayName | Should -BeNullOrEmpty
    }

    It 'Should hold the query it is given, named after it' {
        $Config = New-TabConfigFromTab -SourceTab (New-SourceTab) -CurrentSqlQuery ([PSCustomObject]@{ DoId = "42"; DisplayName = "Accounts"; FullName = "Accounts - 42" })

        $Config.CurrentSqlQuery.DoId | Should -Be "42"
        $Config.CurrentSqlQuery.FullName | Should -Be "Accounts - 42"
        $Config.DisplayName | Should -Be "Accounts"
    }
}
