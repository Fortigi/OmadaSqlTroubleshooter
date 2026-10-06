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

Describe 'Get-DataConnectionReferenceList' {
    # The "{Name} - {DoId}" format had been taken apart by the same regex in three places by the time
    # issue #158 needed a fourth, so there is now one parser and these are its rules.

    It 'parses every entry, in the order the dropdown holds them' {
        $Reference = Get-DataConnectionReferenceList -OptionList @("ODW - 10", "OISES - 20")

        @($Reference.Name) | Should -Be @("ODW", "OISES")
        @($Reference.DoId) | Should -Be @("10", "20")
    }

    It 'keeps the dropdown entry as FullName' {
        (Get-DataConnectionReferenceList -OptionList @("ODW - 10"))[0].FullName | Should -Be "ODW - 10"
    }

    It 'splits from the RIGHT, so a name containing the separator survives' {
        # "Reporting - archive" is a legitimate data connection name. Splitting from the left would
        # make its name "Reporting" and its DoId "archive - 1001572".
        $Reference = Get-DataConnectionReferenceList -OptionList @("Reporting - archive - 1001572")

        $Reference[0].Name | Should -Be "Reporting - archive"
        $Reference[0].DoId | Should -Be "1001572"
    }

    It 'skips entries that are not shaped "{Name} - {DoId}"' {
        $Reference = Get-DataConnectionReferenceList -OptionList @("ODW - 10", "Broken", " ", "Broken - abc", $null)

        @($Reference.Name) | Should -Be @("ODW")
    }

    It 'skips a nameless entry, which is not a data connection' {
        # Issue #165, and a real defect rather than a tidy-up. Set-DataConnection adds a ComboBoxItem
        # whose Content is CurrentDataConnection.FullName, and that is $null on a tab whose connection
        # was never populated - so a blank item lands in the dropdown. The name pattern is `.*` on
        # purpose (see the "Reporting - archive" case above), and `.*` matches nothing at all, so the
        # blank item used to parse as Name="" with DoId=0.
        #
        # Inert until this issue: nothing ENUMERATED this list to fetch anything. The schema preload
        # and the pool-wide refresh turned it into a real authenticated request for database "0",
        # which an E2E refresh caught as a third GetSqlSchema call (ids 0,42,43) for two databases.
        $Reference = Get-DataConnectionReferenceList -OptionList @("ODW - 10", " - 0", "OISES - 20")

        @($Reference.Name) | Should -Be @("ODW", "OISES")
        @($Reference.DoId) | Should -Not -Contain "0"
    }

    It 'skips an entry whose name is only whitespace' {
        $Reference = Get-DataConnectionReferenceList -OptionList @("   - 42", "ODW - 10")

        @($Reference.Name) | Should -Be @("ODW")
    }

    It 'still parses a name that contains the separator, after the nameless guard' {
        # The guard must not cost the behaviour the `.*` pattern exists for.
        $Reference = Get-DataConnectionReferenceList -OptionList @("Reporting - archive - 1001572")

        @($Reference.Name) | Should -Be @("Reporting - archive")
        @($Reference.DoId) | Should -Be @("1001572")
    }

    It 'returns an enumerable of entries, not an array wrapped in an array' {
        # The trap this pins: the function returns its array through the ", $array" idiom, so a
        # caller that wraps the call in @() nests it one level and every .DoId becomes an array of
        # DoIds. That cost real debugging time while building #158's tree.
        $Reference = Get-DataConnectionReferenceList -OptionList @("ODW - 10", "OISES - 20")

        $Reference.Count | Should -Be 2
        $Reference[0] | Should -BeOfType [PSCustomObject]
    }

    It 'returns an empty array for an empty or null option list' {
        (Get-DataConnectionReferenceList -OptionList @()).Count | Should -Be 0
        (Get-DataConnectionReferenceList -OptionList $null).Count | Should -Be 0
    }
}
