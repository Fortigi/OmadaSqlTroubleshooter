#Requires -Version 7.0
BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Invoke-QueryManagerAction.ps1")

    function Get-QueryManagerSelectedQuery { }
    function Open-SqlQueryInTab { param($DoId, $DisplayName) }
    function Open-QueryDetailForm { param($DoId, $DisplayName, $Owner) }
    function Complete-QueryManagerChildWindow { param($Window) }
    function Update-QueryManagerList { param([switch]$Refresh) }
    function Rename-SqlQuery { param($DoId, $DisplayName) }
    function Remove-SavedSqlQuery { param($DoId, $DisplayName) }
    function New-SqlQueryObject { param($ExistingNames) }
    function Open-ChoiceForm { param($Title, $Message, $LeftButtonText, $RightButtonText, $ExtraButtonText, $LeftButtonReturnValue, $RightButtonReturnValue, $ExtraButtonReturnValue) }
    function Open-OmadaQueryObject { param($DoId, $Kind) }
    function Open-SqlQueryInActiveTab { param($DoId, $DisplayName) }
    function Restore-SqlQueryObject { param($DoId, $DisplayName) }
}

Describe 'Invoke-QueryManagerAction' -Tag 'Unit' {
    BeforeEach {
        $Script:QueryManagerForm = [PSCustomObject]@{ Definition = [PSCustomObject]@{ Closed = 0 }; Queries = @([PSCustomObject]@{ DisplayName = "Accounts" }) }
        $Script:QueryManagerForm.Definition | Add-Member -MemberType ScriptMethod -Name Close -Value { $this.Closed++ }
        Mock Get-QueryManagerSelectedQuery { [PSCustomObject]@{ DoId = "42"; DisplayName = "Accounts" } }
        Mock Open-SqlQueryInTab { [PSCustomObject]@{ TabId = "t1" } }
        Mock Open-OmadaQueryObject { }
        Mock Open-SqlQueryInActiveTab { [PSCustomObject]@{ TabId = "t0" } }
        Mock Open-QueryDetailForm { }
        Mock Complete-QueryManagerChildWindow { $false }
        Mock Update-QueryManagerList { }
        Mock Rename-SqlQuery { "Renamed" }
        Mock Remove-SavedSqlQuery { $true }
        Mock New-SqlQueryObject { [PSCustomObject]@{ DoId = "200"; DisplayName = "Fresh" } }
        Mock Open-ChoiceForm { "None" }
        Mock Restore-SqlQueryObject { $true }
    }

    It 'Should do nothing without a selection (<Action>)' -ForEach @(@{ Action = "Open" }, @{ Action = "OpenInTab" }, @{ Action = "Details" }, @{ Action = "Rename" }, @{ Action = "Delete" }, @{ Action = "Restore" }, @{ Action = "Omada" }, @{ Action = "OData" }) {
        Mock Get-QueryManagerSelectedQuery { }

        Invoke-QueryManagerAction -Action $Action

        Should -Invoke Open-SqlQueryInTab -Times 0 -Exactly
        Should -Invoke Rename-SqlQuery -Times 0 -Exactly
        Should -Invoke Remove-SavedSqlQuery -Times 0 -Exactly
        Should -Invoke Open-QueryDetailForm -Times 0 -Exactly
        Should -Invoke Open-OmadaQueryObject -Times 0 -Exactly
        Should -Invoke Open-SqlQueryInActiveTab -Times 0 -Exactly
        Should -Invoke Restore-SqlQueryObject -Times 0 -Exactly
    }

    It 'Should open the selected query in the active tab and close the manager' {
        Invoke-QueryManagerAction -Action Open

        Should -Invoke Open-SqlQueryInActiveTab -Times 1 -Exactly -ParameterFilter { $DoId -eq "42" -and $DisplayName -eq "Accounts" }
        Should -Invoke Open-SqlQueryInTab -Times 0 -Exactly
        $Script:QueryManagerForm.Definition.Closed | Should -Be 1
    }

    It 'Should keep the manager open when the query was not opened in the active tab (cancelled, not connected)' {
        Mock Open-SqlQueryInActiveTab { }

        Invoke-QueryManagerAction -Action Open

        $Script:QueryManagerForm.Definition.Closed | Should -Be 0
    }

    It 'Should open the selected query in a new tab and close the manager' {
        Invoke-QueryManagerAction -Action OpenInTab

        Should -Invoke Open-SqlQueryInTab -Times 1 -Exactly -ParameterFilter { $DoId -eq "42" -and $DisplayName -eq "Accounts" }
        Should -Invoke Open-SqlQueryInActiveTab -Times 0 -Exactly
        $Script:QueryManagerForm.Definition.Closed | Should -Be 1
    }

    It 'Should keep the manager open when no tab could be opened (e.g. all tabs in use)' {
        Mock Open-SqlQueryInTab { }

        Invoke-QueryManagerAction -Action OpenInTab

        Should -Invoke Open-SqlQueryInTab -Times 1 -Exactly
        $Script:QueryManagerForm.Definition.Closed | Should -Be 0
    }

    It 'Should open the selected query''s OData record and keep the manager open' {
        Invoke-QueryManagerAction -Action OData

        Should -Invoke Open-OmadaQueryObject -Times 1 -Exactly -ParameterFilter { $DoId -eq "42" -and $Kind -eq "OData" }
        $Script:QueryManagerForm.Definition.Closed | Should -Be 0
    }

    It 'Should open the selected query in Omada and keep the manager open' {
        Invoke-QueryManagerAction -Action Omada

        Should -Invoke Open-OmadaQueryObject -Times 1 -Exactly -ParameterFilter { $DoId -eq "42" }
        $Script:QueryManagerForm.Definition.Closed | Should -Be 0
    }

    It 'Should show the details on top of the manager and read the list again afterwards' {
        Invoke-QueryManagerAction -Action Details

        Should -Invoke Open-QueryDetailForm -Times 1 -Exactly -ParameterFilter { $DoId -eq "42" -and $Owner -eq $Script:QueryManagerForm.Definition }
        Should -Invoke Update-QueryManagerList -Times 1 -Exactly -ParameterFilter { $Refresh }
    }

    It 'Should not read the list again when the details asked the manager to close' {
        Mock Complete-QueryManagerChildWindow { $true }

        Invoke-QueryManagerAction -Action Details

        Should -Invoke Update-QueryManagerList -Times 0 -Exactly
    }

    It 'Should read the list again only after a <Action> that happened' -ForEach @(
        @{ Action = "Rename"; Mocked = "Rename-SqlQuery"; Nothing = $null }
        @{ Action = "Delete"; Mocked = "Remove-SavedSqlQuery"; Nothing = $false }
    ) {
        Invoke-QueryManagerAction -Action $Action
        Should -Invoke Update-QueryManagerList -Times 1 -Exactly
        Should -Invoke $Mocked -Times 1 -Exactly -ParameterFilter { $DoId -eq "42" -and $DisplayName -eq "Accounts" }

        Mock $Mocked { $Nothing }
        Invoke-QueryManagerAction -Action $Action
        Should -Invoke Update-QueryManagerList -Times 1 -Exactly
    }

    It 'Should create a query against the listed names, show it, and offer to open it' {
        Invoke-QueryManagerAction -Action Create

        Should -Invoke New-SqlQueryObject -Times 1 -Exactly -ParameterFilter { $ExistingNames -contains "Accounts" }
        Should -Invoke Update-QueryManagerList -Times 1 -Exactly -ParameterFilter { $Refresh }
        Should -Invoke Open-ChoiceForm -Times 1 -Exactly -ParameterFilter { $Message -match "'Fresh' was created" }
        Should -Invoke Open-SqlQueryInTab -Times 0 -Exactly
        $Script:QueryManagerForm.Definition.Closed | Should -Be 0
    }

    It 'Should open the created query where asked (<Choice>) and close the manager' -ForEach @(
        @{ Choice = "Open"; Opener = "Open-SqlQueryInActiveTab"; Other = "Open-SqlQueryInTab" }
        @{ Choice = "OpenInTab"; Opener = "Open-SqlQueryInTab"; Other = "Open-SqlQueryInActiveTab" }
    ) {
        Mock Open-ChoiceForm { $Choice }

        Invoke-QueryManagerAction -Action Create

        Should -Invoke Open-ChoiceForm -Times 1 -Exactly -ParameterFilter { $LeftButtonReturnValue -eq "Open" -and $RightButtonReturnValue -eq "OpenInTab" -and $ExtraButtonReturnValue -eq "None" }
        Should -Invoke $Opener -Times 1 -Exactly -ParameterFilter { $DoId -eq "200" -and $DisplayName -eq "Fresh" }
        Should -Invoke $Other -Times 0 -Exactly
        $Script:QueryManagerForm.Definition.Closed | Should -Be 1
    }

    It 'Should restore the selected query and read the list again, but only when it was restored' {
        Invoke-QueryManagerAction -Action Restore
        Should -Invoke Restore-SqlQueryObject -Times 1 -Exactly -ParameterFilter { $DoId -eq "42" -and $DisplayName -eq "Accounts" }
        Should -Invoke Update-QueryManagerList -Times 1 -Exactly

        Mock Restore-SqlQueryObject { $false }
        Invoke-QueryManagerAction -Action Restore
        Should -Invoke Update-QueryManagerList -Times 1 -Exactly
    }

    It 'Should keep the manager open when the created query could not be opened in a tab' {
        Mock Open-ChoiceForm { "OpenInTab" }
        Mock Open-SqlQueryInTab { }

        Invoke-QueryManagerAction -Action Create

        $Script:QueryManagerForm.Definition.Closed | Should -Be 0
    }

    It 'Should do nothing more when no query was created' {
        Mock New-SqlQueryObject { }

        Invoke-QueryManagerAction -Action Create

        Should -Invoke Update-QueryManagerList -Times 0 -Exactly
        Should -Invoke Open-ChoiceForm -Times 0 -Exactly
    }
}
