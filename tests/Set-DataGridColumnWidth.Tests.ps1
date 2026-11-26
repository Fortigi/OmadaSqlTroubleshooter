#Requires -Version 7.0
BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Set-DataGridColumnWidth.ps1")

    function Write-LogOutput { param([Parameter(ValueFromPipeline = $true)]$Message, $LogType) process { $script:Log += , $Message } }

    # 7 px a character, so the widths are easy to reason about.
    $Script:Measure = { param($MeasureGrid, $Text) 7 * ([string]$Text).Length }

    function script:New-TestColumn {
        param([string]$Header, [string]$Path, [string]$SortMemberPath = "")
        [PSCustomObject]@{ Header = $Header; SortMemberPath = $SortMemberPath; Binding = [PSCustomObject]@{ Path = [PSCustomObject]@{ Path = $Path } }; Width = "Auto" }
    }
}

Describe 'Set-DataGridColumnWidth' -Tag 'Unit' {
    It 'Should size each column to its widest value or its header, plus padding' {
        $Grid = [PSCustomObject]@{
            Columns     = @((New-TestColumn -Header "Name" -Path "Name"), (New-TestColumn -Header "A long header" -Path "Short"))
            ItemsSource = @([PSCustomObject]@{ Name = "abc"; Short = "x" }, [PSCustomObject]@{ Name = "abcdefghij"; Short = "y" })
        }

        $Widths = @(Set-DataGridColumnWidth -Grid $Grid -Measure $Script:Measure)

        # Name: the value "abcdefghij" (70 + 14) beats the header "Name" (28 + 26).
        # Short: the header (13 x 7 + 26 = 117) beats the values.
        $Widths | Should -Be @(84, 117)
        $Grid.Columns[0].Width | Should -Be 84
        $Grid.Columns[1].Width | Should -Be 117
    }

    It 'Should measure every row, not only the first ones on screen' {
        $Rows = @(1..500 | ForEach-Object { [PSCustomObject]@{ V = "a" } }) + @([PSCustomObject]@{ V = "z" * 30 })
        $Grid = [PSCustomObject]@{ Columns = @(New-TestColumn -Header "V" -Path "V"); ItemsSource = $Rows }

        @(Set-DataGridColumnWidth -Grid $Grid -Measure $Script:Measure) | Should -Be @(224)
    }

    It 'Should cap a column at the maximum width, and keep it above the minimum' {
        $Grid = [PSCustomObject]@{
            Columns     = @((New-TestColumn -Header "L" -Path "L"), (New-TestColumn -Header "" -Path "E"))
            ItemsSource = @([PSCustomObject]@{ L = "x" * 500; E = "" })
        }

        @(Set-DataGridColumnWidth -Grid $Grid -Measure $Script:Measure -MaxWidth 300 -MinWidth 50) | Should -Be @(300, 50)
    }

    It 'Should measure the rows it is given instead of the grid''s own' {
        $Grid = [PSCustomObject]@{ Columns = @(New-TestColumn -Header "V" -Path "V"); ItemsSource = @([PSCustomObject]@{ V = "a" }) }

        @(Set-DataGridColumnWidth -Grid $Grid -Item @([PSCustomObject]@{ V = "x" * 20 }) -Measure $Script:Measure) | Should -Be @(154)
    }

    It 'Should read no more than the maximum number of rows' {
        $Rows = @([PSCustomObject]@{ V = "a" }, [PSCustomObject]@{ V = "z" * 30 })
        $Grid = [PSCustomObject]@{ Columns = @(New-TestColumn -Header "V" -Path "V"); ItemsSource = $Rows }

        @(Set-DataGridColumnWidth -Grid $Grid -Measure $Script:Measure -MaxRows 1) | Should -Be @(40)
    }

    It 'Should read a DataTable''s rows by column name' {
        $Table = [System.Data.DataTable]::new()
        [void]$Table.Columns.Add("Col", [string])
        [void]$Table.Rows.Add("abcdefghijkl")
        [void]$Table.Rows.Add([System.DBNull]::Value)
        $Grid = [PSCustomObject]@{ Columns = @(New-TestColumn -Header "Col" -Path "Col"); ItemsSource = $Table.DefaultView }

        @(Set-DataGridColumnWidth -Grid $Grid -Measure $Script:Measure) | Should -Be @(98)
    }

    It 'Should size a column without a binding by its header alone' {
        $Grid = [PSCustomObject]@{ Columns = @([PSCustomObject]@{ Header = "Template"; SortMemberPath = ""; Binding = $null; Width = "Auto" }); ItemsSource = @([PSCustomObject]@{ V = "x" * 50 }) }

        @(Set-DataGridColumnWidth -Grid $Grid -Measure $Script:Measure) | Should -Be @(82)
    }
}

Describe 'Get-DataGridColumnKey' -Tag 'Unit' {
    It 'Should read <Case>' -ForEach @(
        @{ Case = 'the sort member first'; Sort = "Sorted"; Path = "Bound"; Expected = "Sorted" }
        @{ Case = 'the binding path without one'; Sort = ""; Path = "Bound"; Expected = "Bound" }
        @{ Case = 'a bracketed path without its brackets'; Sort = ""; Path = "[My column]"; Expected = "My column" }
    ) {
        Get-DataGridColumnKey -Column (New-TestColumn -Header "h" -Path $Path -SortMemberPath $Sort) | Should -BeExactly $Expected
    }
}

Describe 'Get-DataGridColumnTextCandidate' -Tag 'Unit' {
    BeforeAll {
        $script:Rows = @(
            [PSCustomObject]@{ V = "short`r`na much longer second line" }
            [PSCustomObject]@{ V = $null }
            [PSCustomObject]@{ V = "middle value" }
            [PSCustomObject]@{ V = "middle value" }
            [PSCustomObject]@{ V = "tiny" }
            [PSCustomObject]@{ V = 12345 }
        )
    }

    It 'Should give the longest distinct values, longest line of each, longest first (<Case>)' -ForEach @(
        @{ Case = 'compiled'; Compiled = $true }
        @{ Case = 'PowerShell'; Compiled = $false }
    ) {
        if (-not $Compiled) {
            Mock Initialize-DataGridColumnTextType { $false }
        }

        Get-DataGridColumnTextCandidate -Row $script:Rows -Key "V" -Count 3 | Should -Be @("a much longer second line", "middle value", "12345")
    }

    It 'Should read a DataTable''s rows the same way (<Case>)' -ForEach @(
        @{ Case = 'compiled'; Compiled = $true }
        @{ Case = 'PowerShell'; Compiled = $false }
    ) {
        if (-not $Compiled) {
            Mock Initialize-DataGridColumnTextType { $false }
        }
        $Table = [System.Data.DataTable]::new()
        [void]$Table.Columns.Add("V", [string])
        "aa", "aaaa", "a" | ForEach-Object { [void]$Table.Rows.Add($_) }

        Get-DataGridColumnTextCandidate -Row @($Table.DefaultView) -Key "V" -Count 2 | Should -Be @("aaaa", "aa")
        Get-DataGridColumnTextCandidate -Row @($Table.DefaultView) -Key "Missing" -Count 2 | Should -BeNullOrEmpty
    }

    It 'Should keep a one-character value in the PowerShell path' {
        Mock Initialize-DataGridColumnTextType { $false }
        Get-DataGridColumnTextCandidate -Row @([PSCustomObject]@{ V = "x" }, [PSCustomObject]@{ V = "" }) -Key "V" | Should -Be @("x")
    }

    It 'Should give nothing without a key' {
        Get-DataGridColumnTextCandidate -Row $script:Rows -Key "" | Should -BeNullOrEmpty
    }
}

Describe 'Initialize-DataGridColumnTextType' -Tag 'Unit' {
    It 'Should build the helper, and not again once it is there' {
        Initialize-DataGridColumnTextType | Should -BeTrue
        "Fortigi.DataGridColumnText" -as [type] | Should -Not -BeNullOrEmpty

        Mock Add-Type { throw "should not be built again" }
        Initialize-DataGridColumnTextType | Should -BeTrue
        Should -Invoke Add-Type -Times 0 -Exactly
    }

    It 'Should remember a failed build for the session, and say false' {
        # The helper type exists in this session already (the test above built it), so the function is
        # run as a copy that looks for a type that is never built - "not there".
        $Script:DataGridColumnTextTypeFailed = $true
        Mock Add-Type { }
        $Original = ${function:Initialize-DataGridColumnTextType}.ToString()
        try {
            ${function:Test-FailedBuild} = $Original -replace 'Fortigi\.DataGridColumnText', 'Fortigi.NeverBuilt'
            Test-FailedBuild | Should -BeFalse
            Should -Invoke Add-Type -Times 0 -Exactly

            $Script:DataGridColumnTextTypeFailed = $null
            Mock Add-Type { throw "no compiler" }
            Test-FailedBuild | Should -BeFalse
            $Script:DataGridColumnTextTypeFailed | Should -BeTrue
        }
        finally {
            $Script:DataGridColumnTextTypeFailed = $null
        }
    }
}

Describe 'Update-DataGridColumnWidth' -Tag 'Unit' {
    BeforeEach {
        $script:Log = @()
    }

    It 'Should size the grid, with the rows given or the grid''s own' {
        Mock Set-DataGridColumnWidth { }

        Update-DataGridColumnWidth -Grid ([PSCustomObject]@{ Name = "G" })
        Update-DataGridColumnWidth -Grid ([PSCustomObject]@{ Name = "G" }) -Item @(1)

        Should -Invoke Set-DataGridColumnWidth -Times 1 -Exactly -ParameterFilter { $null -eq $Item }
        Should -Invoke Set-DataGridColumnWidth -Times 1 -Exactly -ParameterFilter { $Item -contains 1 }
    }

    It 'Should log a failure instead of passing it on' {
        Mock Set-DataGridColumnWidth { throw "no WPF" }

        { Update-DataGridColumnWidth -Grid ([PSCustomObject]@{ Name = "G" }) } | Should -Not -Throw
        $script:Log | Should -Match "Could not size the columns of grid 'G': no WPF"
    }

    It 'Should do nothing without a grid' {
        Mock Set-DataGridColumnWidth { }
        Update-DataGridColumnWidth -Grid $null
        Should -Invoke Set-DataGridColumnWidth -Times 0 -Exactly
    }
}
