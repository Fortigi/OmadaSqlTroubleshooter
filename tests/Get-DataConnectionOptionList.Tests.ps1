BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-DataConnectionOptionList.ps1"
    . $Command
}

Describe 'Get-DataConnectionOptionList' {
    It 'parses each option into "{DisplayName} - {DoId}" in order' {
        $Html = '<select><option value="1001572" data-uid="abc">OISES</option><option value="2003044" data-uid="def">ODW</option></select>'
        $Result = Get-DataConnectionOptionList -Html $Html
        $Result | Should -Be @("OISES - 1001572", "ODW - 2003044")
    }

    It 'returns an empty array for empty input' {
        (Get-DataConnectionOptionList -Html "").Count | Should -Be 0
    }

    It 'returns an empty array for null input' {
        (Get-DataConnectionOptionList -Html $null).Count | Should -Be 0
    }

    It 'returns an empty array when there are no options' {
        (Get-DataConnectionOptionList -Html "<select></select>").Count | Should -Be 0
    }

    It 'de-duplicates repeated options while preserving order' {
        $Html = '<option value="10" data-uid="a">OISES</option><option value="20" data-uid="b">ODW</option><option value="10" data-uid="a">OISES</option>'
        $Result = Get-DataConnectionOptionList -Html $Html
        $Result | Should -Be @("OISES - 10", "ODW - 20")
    }

    It 'returns a single-element array (not unrolled to a scalar) for one option' {
        $Result = Get-DataConnectionOptionList -Html '<option value="10" data-uid="a">OISES</option>'
        , $Result | Should -BeOfType [System.Array]
        $Result.Count | Should -Be 1
        $Result[0] | Should -Be "OISES - 10"
    }
}
