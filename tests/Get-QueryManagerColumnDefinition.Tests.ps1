#Requires -Version 7.0
BeforeAll {
    . (Join-Path $PSScriptRoot "QueryManager.Shared.ps1")
    $Script:UiPath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "ui")
}

Describe 'Get-QueryManagerColumnDefinition' -Tag 'Unit' {
    It 'Should define the columns asked for, in order' {
        @(Get-QueryManagerColumnDefinition).Header | Should -Be @("Id", "Display name", "Connection", "Created", "Created by", "Changed", "Changed by", "Is Deleted", "Deleted", "UId")
        @(Get-QueryManagerColumnDefinition).Field | Should -Be @("Id", "DisplayName", "C_SQLTROUBLESHOOTING_DATACONNECTION", "CreateTime", "", "ChangeTime", "", "Deleted", "DeleteTime", "UId")
    }

    It 'Should match the query manager''s grid columns, header and binding' {
        [xml]$Xaml = Get-Content -Path (Join-Path $Script:UiPath "QueryManagerForm.xaml") -Raw
        $Grid = $Xaml.SelectSingleNode("//*[local-name()='DataGrid' and @*[local-name()='Name']='DataGridQueries']")
        $Columns = @($Grid.SelectNodes(".//*[local-name()='DataGridTextColumn']"))

        $Columns.Header | Should -Be @(Get-QueryManagerColumnDefinition).Header
        @($Columns | ForEach-Object { $_.GetAttribute("Binding") -replace '^\{Binding (\w+)\}$', '$1' }) | Should -Be @(Get-QueryManagerColumnDefinition).Name
        $Grid.GetAttribute("AutoGenerateColumns") | Should -Be "False"
    }
}

Describe 'ConvertTo-QueryManagerColumnValue' -Tag 'Unit' {
    It 'Should show <Kind> <Case> as <Expected>' -ForEach @(
        @{ Kind = "Id"; Case = "text"; Value = "42"; Expected = 42 }
        @{ Kind = "Text"; Case = "a number"; Value = 5; Expected = "5" }
        @{ Kind = "Bool"; Case = "true"; Value = $true; Expected = "Yes" }
        @{ Kind = "Bool"; Case = "false"; Value = $false; Expected = "No" }
        @{ Kind = "Bool"; Case = "text true"; Value = "True"; Expected = "Yes" }
        @{ Kind = "Owner"; Case = "a name"; Value = "CORP\ann"; Expected = "CORP\ann" }
        @{ Kind = "Text"; Case = "nothing"; Value = $null; Expected = "" }
        @{ Kind = "Text"; Case = "blank"; Value = "  "; Expected = "" }
        @{ Kind = "Bool"; Case = "nothing"; Value = $null; Expected = "" }
    ) {
        ConvertTo-QueryManagerColumnValue -Kind $Kind -Value $Value | Should -Be $Expected
    }

    It 'Should give no id for none' {
        ConvertTo-QueryManagerColumnValue -Kind Id -Value $null | Should -BeNullOrEmpty
        ConvertTo-QueryManagerColumnValue -Kind Id -Value 42 | Should -BeOfType [long]
    }

    It 'Should show a reference by its display name, or as the list shows it without one' {
        ConvertTo-QueryManagerColumnValue -Kind Reference -Value ([PSCustomObject]@{ Id = 3; DisplayName = "OISES" }) | Should -BeExactly "OISES"
        ConvertTo-QueryManagerColumnValue -Kind Reference -Value ([PSCustomObject]@{ Id = 3 }) | Should -BeExactly "3"
    }

    It 'Should show a date as yyyy-MM-dd HH:mm:ss' {
        ConvertTo-QueryManagerColumnValue -Kind Date -Value ([datetime]::new(2026, 1, 2, 3, 4, 5)) | Should -BeExactly "2026-01-02 03:04:05"
    }
}

Describe 'ConvertTo-QueryManagerDate' -Tag 'Unit' {
    It 'Should show an unspecified time as given' {
        ConvertTo-QueryManagerDate -Value ([datetime]::new(2026, 1, 2, 3, 4, 5, [DateTimeKind]::Unspecified)) | Should -BeExactly "2026-01-02 03:04:05"
    }

    It 'Should show a UTC time, and text with an offset, in local time' {
        $Utc = [datetime]::new(2026, 1, 2, 3, 4, 5, [DateTimeKind]::Utc)
        $Expected = $Utc.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")

        ConvertTo-QueryManagerDate -Value $Utc | Should -BeExactly $Expected
        ConvertTo-QueryManagerDate -Value ([DateTimeOffset]::new($Utc)) | Should -BeExactly $Expected
        ConvertTo-QueryManagerDate -Value "2026-01-02T03:04:05Z" | Should -BeExactly $Expected
    }

    It 'Should show text that is not a time as it is' {
        ConvertTo-QueryManagerDate -Value "yesterday" | Should -BeExactly "yesterday"
    }
}

Describe 'ConvertTo-QueryManagerRow' -Tag 'Unit' {
    It 'Should give every column a value, by name' {
        $Row = ConvertTo-QueryManagerRow -Query ([PSCustomObject]@{ Id = 7; DisplayName = "A" }) -Ownership @{ "7" = [PSCustomObject]@{ CreatedBy = "ann"; ChangedBy = "bob" } }

        @($Row.Keys) | Should -Be @(Get-QueryManagerColumnDefinition).Name
        $Row["Id"] | Should -Be 7
        $Row["CreatedBy"] | Should -Be "ann"
        $Row["ChangedBy"] | Should -Be "bob"
    }

    It 'Should leave the owners empty for a query the ownership does not know (<Case>)' -ForEach @(
        @{ Case = 'other queries'; Ownership = @{ "8" = [PSCustomObject]@{ CreatedBy = "ann"; ChangedBy = "bob" } } }
        @{ Case = 'none'; Ownership = $null }
    ) {
        $Row = ConvertTo-QueryManagerRow -Query ([PSCustomObject]@{ Id = 7 }) -Ownership $Ownership
        $Row["CreatedBy"] | Should -Be ""
    }
}

Describe 'Get-QueryOwnership' -Tag 'Unit' {
    It 'Should read who created and changed each query from the view''s mapped columns' {
        $Mapping = [PSCustomObject]@{ SqlQueryDoId = "c-13"; SqlQueryCreatedBy = "c-2"; SqlQueryChangedBy = "c-4" }
        $Rows = @(
            [PSCustomObject]@{ "c-13" = 8801; "c-2" = "MOCK\serviceaccount"; "c-4" = "MOCK\other" }
            [PSCustomObject]@{ "c-13" = $null; "c-2" = "x"; "c-4" = "y" }
            $null
        )

        $Ownership = Get-QueryOwnership -ViewRow $Rows -Mapping $Mapping

        $Ownership.Count | Should -Be 1
        $Ownership["8801"].CreatedBy | Should -Be "MOCK\serviceaccount"
        $Ownership["8801"].ChangedBy | Should -Be "MOCK\other"
    }

    It 'Should give none for no rows' {
        (Get-QueryOwnership -ViewRow @() -Mapping ([PSCustomObject]@{ SqlQueryDoId = "c-13" })).Count | Should -Be 0
    }
}

Describe 'Test-QueryOwnedBy' -Tag 'Unit' {
    BeforeAll {
        $script:Owner = [PSCustomObject]@{ CreatedBy = "ann"; ChangedBy = "bob" }
    }

    It 'Should answer <Expected> for <User> with created <Created> and updated <Updated>' -ForEach @(
        @{ User = "ann"; Created = $false; Updated = $false; Expected = $true }
        @{ User = "ann"; Created = $true; Updated = $false; Expected = $true }
        @{ User = "bob"; Created = $true; Updated = $false; Expected = $false }
        @{ User = "bob"; Created = $false; Updated = $true; Expected = $true }
        @{ User = "ann"; Created = $false; Updated = $true; Expected = $false }
        @{ User = "ann"; Created = $true; Updated = $true; Expected = $true }
        @{ User = "bob"; Created = $true; Updated = $true; Expected = $true }
        @{ User = "eve"; Created = $true; Updated = $true; Expected = $false }
        @{ User = ""; Created = $true; Updated = $true; Expected = $true }
    ) {
        Test-QueryOwnedBy -Owner $script:Owner -UserName $User -Created $Created -Updated $Updated | Should -Be $Expected
    }

    It 'Should keep out a query nobody is known to own while a filter is on' {
        Test-QueryOwnedBy -Owner $null -UserName "ann" -Created $true | Should -BeFalse
    }
}
