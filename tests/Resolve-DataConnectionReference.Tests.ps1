BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Resolve-DataConnectionReference.ps1")
}

Describe 'Resolve-DataConnectionReference' {
    BeforeEach {
        $Script:OptionList = @("OISES - 1001572", "ODW - 2003044", "OISLOG - 3004055")
    }

    It 'resolves a name to its data connection DoId' {
        $Result = Resolve-DataConnectionReference -Name "ODW" -OptionList $Script:OptionList
        $Result.Name | Should -Be "ODW"
        $Result.DoId | Should -Be "2003044"
        $Result.FullName | Should -Be "ODW - 2003044"
    }

    It 'matches case-insensitively (issue #152 criterion 3)' {
        (Resolve-DataConnectionReference -Name "oislog" -OptionList $Script:OptionList).DoId | Should -Be "3004055"
        (Resolve-DataConnectionReference -Name "OisLog" -OptionList $Script:OptionList).DoId | Should -Be "3004055"
    }

    It 'reports the connection in its own casing, not the casing that was typed' {
        (Resolve-DataConnectionReference -Name "oises" -OptionList $Script:OptionList).Name | Should -Be "OISES"
    }

    It 'returns null for a name that matches no connection (criterion 9)' {
        Resolve-DataConnectionReference -Name "Nope" -OptionList $Script:OptionList | Should -BeNullOrEmpty
    }

    It 'splits from the right so a connection name containing " - " still resolves' {
        # "Reporting - archive" would otherwise resolve to the name "Reporting" with a DoId of
        # "archive - 2003044", which is not a DoId at all.
        $Result = Resolve-DataConnectionReference -Name "Reporting - archive" -OptionList @("Reporting - archive - 2003044")
        $Result.Name | Should -Be "Reporting - archive"
        $Result.DoId | Should -Be "2003044"
    }

    It 'returns the first match when the list holds the same name twice' {
        (Resolve-DataConnectionReference -Name "ODW" -OptionList @("ODW - 10", "ODW - 20")).DoId | Should -Be "10"
    }

    It 'ignores entries that are not shaped "{Name} - {DoId}"' {
        Resolve-DataConnectionReference -Name "Broken" -OptionList @("Broken", " - ", "Broken - abc") | Should -BeNullOrEmpty
    }

    It 'returns null for an empty or null name' {
        Resolve-DataConnectionReference -Name "" -OptionList $Script:OptionList | Should -BeNullOrEmpty
        Resolve-DataConnectionReference -Name $null -OptionList $Script:OptionList | Should -BeNullOrEmpty
    }

    It 'returns null for an empty or null option list' {
        Resolve-DataConnectionReference -Name "ODW" -OptionList @() | Should -BeNullOrEmpty
        Resolve-DataConnectionReference -Name "ODW" -OptionList $null | Should -BeNullOrEmpty
    }
}
