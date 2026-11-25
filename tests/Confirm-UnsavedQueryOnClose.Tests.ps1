#Requires -Version 7.0
# Closing the application asks about every tab with unsaved work; Cancel keeps the window open.

BeforeAll {
    . (Join-Path $PSScriptRoot "CloseFlow.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Confirm-UnsavedQueryOnClose.ps1")

    function Request-TabQuerySave { param($TabSession, $Kind, [switch]$ClosingApplication) }

    function script:New-CloseTab {
        param($Id, $DoId = 42, $Text = "SELECT 1", [bool]$Dirty = $true, [bool]$Connected = $true)
        return [PSCustomObject]@{
            Id               = $Id
            DisplayName      = $Id
            IsDirty          = $Dirty
            EditorText       = $Text
            ConnectionStatus = $Connected
            AppConfig        = [PSCustomObject]@{ CurrentSqlQuery = [PSCustomObject]@{ DoId = $DoId } }
        }
    }
}

Describe 'Confirm-UnsavedQueryOnClose' -Tag 'Unit' {
    BeforeEach {
        $script:QueryLog.Clear()
        $Script:Tabs = @(
            New-CloseTab -Id "saved-dirty"
            New-CloseTab -Id "clean" -Dirty $false
            New-CloseTab -Id "empty" -Text ""
            New-CloseTab -Id "offline" -DoId $null -Connected $false
            New-CloseTab -Id "adhoc" -DoId $null
        )
        $Script:ActiveTabId = "clean"
        $Script:ConnectionStatus = $true
        Mock Request-TabQuerySave { "Saved" }
        Mock Set-ActiveTabContext { $Script:ActiveTabId = $TabSession.Id }
    }

    It 'Should ask about exactly the tabs with something that can be saved, in order' {
        Confirm-UnsavedQueryOnClose | Should -BeTrue

        Should -Invoke Request-TabQuerySave -Times 2 -Exactly
        Should -Invoke Request-TabQuerySave -Times 1 -Exactly -ParameterFilter { $TabSession.Id -eq "saved-dirty" -and $Kind -eq "SaveExisting" -and $ClosingApplication }
        Should -Invoke Request-TabQuerySave -Times 1 -Exactly -ParameterFilter { $TabSession.Id -eq "adhoc" -and $Kind -eq "SaveNew" -and $ClosingApplication }
    }

    It 'Should make each tab active before asking about it, and restore the active tab afterwards' {
        $null = Confirm-UnsavedQueryOnClose

        Should -Invoke Set-ActiveTabContext -Times 1 -Exactly -ParameterFilter { $TabSession.Id -eq "saved-dirty" }
        Should -Invoke Set-ActiveTabContext -Times 1 -Exactly -ParameterFilter { $TabSession.Id -eq "adhoc" }
        $Script:ActiveTabId | Should -Be "clean"
    }

    It 'Should go on closing when the user does not save' {
        Mock Request-TabQuerySave { "Discarded" }

        Confirm-UnsavedQueryOnClose | Should -BeTrue
    }

    It 'Should stop at the first Cancel and keep the window open' {
        Mock Request-TabQuerySave { "Cancel" }

        Confirm-UnsavedQueryOnClose | Should -BeFalse
        Should -Invoke Request-TabQuerySave -Times 1 -Exactly
        $Script:ActiveTabId | Should -Be "clean"
    }

    It 'Should not ask anything when nothing is unsaved' {
        $Script:Tabs = @(New-CloseTab -Id "clean" -Dirty $false)

        Confirm-UnsavedQueryOnClose | Should -BeTrue
        Should -Invoke Request-TabQuerySave -Times 0 -Exactly
    }

    It 'Should use the live connection state of the active tab' {
        $Script:Tabs = @(New-CloseTab -Id "active" -Connected $false)
        $Script:ActiveTabId = "active"
        $Script:ConnectionStatus = $true

        $null = Confirm-UnsavedQueryOnClose

        Should -Invoke Request-TabQuerySave -Times 1 -Exactly
    }

    It 'Should close anyway, with a warning, when asking fails' {
        Mock Request-TabQuerySave { throw "boom" }

        Confirm-UnsavedQueryOnClose | Should -BeTrue
        ($script:QueryLog | Where-Object LogType -eq "WARNING").Message | Should -Match "closing anyway: boom"
    }
}
