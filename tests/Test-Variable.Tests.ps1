
BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Test-Variable.ps1"
    . $Command
    $Script:Tracer = [System.Diagnostics.Trace]
}

Describe 'Test-Variable' {
    BeforeAll {

        $Global:MainForm1 = @{
            Elements = @{
                ButtonSaveQuery = @{
                    IsEnabled = $true
                }
            }
        }

        $Global:MainForm2 = [PSCustomObject]@{
            Elements = [PSCustomObject]@{
                ButtonSaveQuery = [PSCustomObject]@{
                    IsEnabled = $true
                }
            }
        }

        $Global:MainForm3 = @{
            Elements = [PSCustomObject]@{
                ButtonSaveQuery = @{
                    IsEnabled = "test"
                }
            }
        }

        $Global:MainForm4 = @{
            Elements = [PSCustomObject]@{
                ButtonSaveQuery = @{
                    IsEnabled = $null
                }
            }
        }

        $Global:Test = "test"
    }

    It 'should return true for existing variable and attribute chain1' {
        '$Global:MainForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-Variable | Should -Be $true
    }

    It 'should return false for non-existing variable1' {
        ('$Global:NonExistingVariable' | Test-Variable).VariableExists | Should -Be $false
    }
    It 'should return false for non-existing variable2' {
        ('$Global:NonExistingVariable' | Test-Variable).AttributeExists | Should -Be $false
    }

    It 'should return true for existing variable but non-existing attribute chain1' {
        ('$Global:MainForm1.Elements.NonExistingAttribute' | Test-Variable).VariableExists | Should -Be $true
    }
    It 'should return false for existing variable but non-existing attribute chain2' {
        ('$Global:MainForm1.Elements.NonExistingAttribute' | Test-Variable).AttributeExists | Should -Be $false
    }

    # It 'should return true for existing variable and attribute chain with ExcludeVariable1' {
    #     '$Global:MainForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-Variable -ExcludeVariable | Should -Be $true
    # }

    # It 'should return true for existing variable and attribute chain with ExcludeAttribute2' {
    #     '$Global:MainForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-Variable -ExcludeAttribute | Should -Be $true
    # }

    It 'should return false for non-existing variable with ExcludeVariable1' {
        '$Global:NonExistingVariable' | Test-Variable -ExcludeVariable | Should -Be $false
    }

    # It 'should return false for non-existing attribute chain with ExcludeAttribute1' {
    #     '$Global:MainForm1.Elements.NonExistingAttribute' | Test-Variable -ExcludeAttribute | Should -Be $false
    # }
}
