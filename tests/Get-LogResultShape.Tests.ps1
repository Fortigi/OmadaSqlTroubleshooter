BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-LogResultShape.ps1"
    . $Command
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    function New-FakeRows {
        param([int]$Count)
        1..$Count | ForEach-Object {
            [PSCustomObject]@{
                Id          = $_
                DisplayName = "Employee-$_"
                Email       = "user$_@contoso.com"
            }
        }
    }
}

Describe 'Get-LogResultShape' {

    It 'reports the row count' {
        Get-LogResultShape -InputObject (New-FakeRows -Count 42) | Should -Match "42 row"
    }

    It 'reports the column count and the column names' {
        $Result = Get-LogResultShape -InputObject (New-FakeRows -Count 3)

        $Result | Should -Match "3 column"
        $Result | Should -Match "Id"
        $Result | Should -Match "DisplayName"
        $Result | Should -Match "Email"
    }

    It 'never emits a cell value' {
        # This is the whole point: an exported log may be attached to a support ticket.
        $Result = Get-LogResultShape -InputObject (New-FakeRows -Count 10)

        $Result | Should -Not -Match "Employee-"
        $Result | Should -Not -Match "contoso.com"
    }

    It 'handles a single row that is not wrapped in an array' {
        $Result = Get-LogResultShape -InputObject ([PSCustomObject]@{ Id = 1; DisplayName = "Solo" })

        $Result | Should -Match "1 row"
        $Result | Should -Not -Match "Solo"
    }

    It 'reports an empty result set as zero rows' {
        Get-LogResultShape -InputObject @() | Should -Match "0 row"
    }

    It 'handles $null without throwing' {
        { Get-LogResultShape -InputObject $null } | Should -Not -Throw
        Get-LogResultShape -InputObject $null | Should -Match "0 row"
    }

    It 'caps the number of column names it lists' {
        $Wide = [PSCustomObject]@{}
        1..40 | ForEach-Object { $Wide | Add-Member -NotePropertyName "Column$_" -NotePropertyValue $_ }

        $Result = Get-LogResultShape -InputObject $Wide

        $Result | Should -Match "40 column"
        # Only the first batch of names is listed, with an explicit marker that more exist.
        $Result | Should -Match "more"
    }

    It 'always returns a string, never $null' {
        Get-LogResultShape -InputObject (New-FakeRows -Count 1) | Should -BeOfType [string]
    }
}
