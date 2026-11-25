#Requires -Version 7.0
BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Update-MainMenuState.ps1")
    . (Join-Path $PrivatePath "Resolve-MainMenuItemState.ps1")

    function Get-ActiveTabSession { $script:ActiveTab }
    function Update-DataGridQueryResultContextMenuState { }
    function Get-MainMenuResultItem { }

    function New-TestMenuItem {
        param($Tag, $Header = "Original")
        [PSCustomObject]@{ Tag = $Tag; Header = $Header; IsEnabled = $null; IsChecked = "untouched" }
    }
}

Describe 'Update-MainMenuState' -Tag 'Unit' {
    BeforeEach {
        $script:ActiveTab = [PSCustomObject]@{
            Elements = @{
                ButtonSaveQuery          = [PSCustomObject]@{ IsEnabled = $true }
                ButtonConnect            = [PSCustomObject]@{ IsEnabled = $true }
                ButtonConnectText        = [PSCustomObject]@{ Text = "_Disconnect" }
                CheckboxMyCreatedQueries = [PSCustomObject]@{ IsEnabled = $true; IsChecked = $true }
            }
        }
        $Script:Tabs = @("a", "b")
        Mock Update-DataGridQueryResultContextMenuState { }
        Mock Get-MainMenuResultItem { @{ Copy = [PSCustomObject]@{ IsEnabled = $true } } }
    }

    It 'Should apply each tagged item''s state and leave the rest alone' {
        $Save = New-TestMenuItem "Button:ButtonSaveQuery"
        $Connect = New-TestMenuItem "Button:ButtonConnect"
        $Filter = New-TestMenuItem "Check:CheckboxMyCreatedQueries"
        $Next = New-TestMenuItem "Tab:Next"
        $Separator = [PSCustomObject]@{ Tag = $null; IsEnabled = "untouched" }
        $Untagged = [PSCustomObject]@{ Tag = "NoKind"; IsEnabled = "untouched" }

        Update-MainMenuState -MenuItem ([PSCustomObject]@{ Items = @($Save, $Connect, $Filter, $Next, $Separator, $Untagged) })

        $Save.IsEnabled | Should -BeTrue
        $Save.Header | Should -BeExactly "Original"
        $Save.IsChecked | Should -BeExactly "untouched"
        $Connect.Header | Should -BeExactly "_Disconnect"
        $Filter.IsChecked | Should -BeTrue
        $Next.IsEnabled | Should -BeTrue
        $Separator.IsEnabled | Should -BeExactly "untouched"
        $Untagged.IsEnabled | Should -BeExactly "untouched"
    }

    It 'Should pass the number of open tabs' {
        $Script:Tabs = @("a")
        $Next = New-TestMenuItem "Tab:Next"

        Update-MainMenuState -MenuItem ([PSCustomObject]@{ Items = @($Next) })

        $Next.IsEnabled | Should -BeFalse
    }

    It 'Should disable tab-bound items without an active tab' {
        $script:ActiveTab = $null
        $Save = New-TestMenuItem "Button:ButtonSaveQuery"
        $Exit = New-TestMenuItem "App:Exit"

        Update-MainMenuState -MenuItem ([PSCustomObject]@{ Items = @($Save, $Exit) })

        $Save.IsEnabled | Should -BeFalse
        $Exit.IsEnabled | Should -BeTrue
    }

    It 'Should refresh the result context menu only for a menu with result items' {
        $Copy = New-TestMenuItem "Result:Copy"

        Update-MainMenuState -MenuItem ([PSCustomObject]@{ Items = @(New-TestMenuItem "Button:ButtonSaveQuery") })
        Should -Invoke Update-DataGridQueryResultContextMenuState -Times 0 -Exactly
        Should -Invoke Get-MainMenuResultItem -Times 0 -Exactly

        Update-MainMenuState -MenuItem ([PSCustomObject]@{ Items = @($Copy) })
        Should -Invoke Update-DataGridQueryResultContextMenuState -Times 1 -Exactly
        $Copy.IsEnabled | Should -BeTrue
    }
}
