
BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Test-Variable.ps1"
    . $Command
}

Describe 'Test-Variable' {
    BeforeAll {

        $Global:MainWindowForm1 = @{
            Elements = @{
                ButtonSaveQuery = @{
                    IsEnabled = $true
                }
            }
        }

        $Global:MainWindowForm2 = [pscustomobject]@{
            Elements = [pscustomobject]@{
                ButtonSaveQuery = [pscustomobject]@{
                    IsEnabled = $true
                }
            }
        }

        $Global:MainWindowForm3 = @{
            Elements = [pscustomobject]@{
                ButtonSaveQuery = @{
                    IsEnabled = "test"
                }
            }
        }

        $Global:MainWindowForm4 = @{
            Elements = [pscustomobject]@{
                ButtonSaveQuery = @{
                    IsEnabled = $null
                }
            }
        }

        $Global:Test = "test"
    }

    It 'should return true for existing variable and attribute chain1' {
        '$Global:MainWindowForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-Variable | Should -Be $true
    }

    It 'should return false for non-existing variable1' {
        ('$Global:NonExistingVariable' | Test-Variable).VariableExists | Should -Be $false
    }
    It 'should return false for non-existing variable2' {
        ('$Global:NonExistingVariable' | Test-Variable).AttributeExists | Should -Be $false
    }

    It 'should return true for existing variable but non-existing attribute chain1' {
        ('$Global:MainWindowForm1.Elements.NonExistingAttribute' | Test-Variable).VariableExists | Should -Be $true
    }
    It 'should return false for existing variable but non-existing attribute chain2' {
        ('$Global:MainWindowForm1.Elements.NonExistingAttribute' | Test-Variable).AttributeExists | Should -Be $false
    }

    # It 'should return true for existing variable and attribute chain with ExcludeVariable1' {
    #     '$Global:MainWindowForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-Variable -ExcludeVariable | Should -Be $true
    # }

    # It 'should return true for existing variable and attribute chain with ExcludeAttribute2' {
    #     '$Global:MainWindowForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-Variable -ExcludeAttribute | Should -Be $true
    # }

    It 'should return false for non-existing variable with ExcludeVariable1' {
        '$Global:NonExistingVariable' | Test-Variable -ExcludeVariable | Should -Be $false
    }

    # It 'should return false for non-existing attribute chain with ExcludeAttribute1' {
    #     '$Global:MainWindowForm1.Elements.NonExistingAttribute' | Test-Variable -ExcludeAttribute | Should -Be $false
    # }
}
