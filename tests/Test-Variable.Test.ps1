
# Description: Test-VariableAndAttribute function tests.




$Global:MainFormForm1 = @{
    Elements = @{
        ButtonSaveQuery = @{
            IsEnabled = $true
        }
    }
}

$Global:MainFormForm2 = [PSCustomObject]@{
    Elements = [PSCustomObject]@{
        ButtonSaveQuery = [PSCustomObject]@{
            IsEnabled = $true
        }
    }
}

$Global:MainFormForm3 = @{
    Elements = [PSCustomObject]@{
        ButtonSaveQuery = @{
            IsEnabled = "test"
        }
    }
}

$Global:MainFormForm4 = @{
    Elements = [PSCustomObject]@{
        ButtonSaveQuery = @{
            IsEnabled = $null
        }
    }
}

$Test = "test"


'$Global:MainFormForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute
'$Global:MainFormForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable
'$Global:MainFormForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeAttribute
'$Global:MainFormForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable -ExcludeAttribute

'$Global:MainFormForm2.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute
'$Global:MainFormForm2.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable
'$Global:MainFormForm2.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeAttribute
'$Global:MainFormForm2.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable -ExcludeAttribute

'$Global:MainFormForm3.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute
'$Global:MainFormForm3.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable
'$Global:MainFormForm3.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeAttribute
'$Global:MainFormForm3.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable -ExcludeAttribute

'$Global:MainFormForm4.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute
'$Global:MainFormForm4.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable
'$Global:MainFormForm4.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeAttribute
'$Global:MainFormForm4.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable -ExcludeAttribute

'$Test' | Test-VariableAndAttribute
'$Test' | Test-VariableAndAttribute -ExcludeVariable
'$Test' | Test-VariableAndAttribute -ExcludeAttribute
'$Test' | Test-VariableAndAttribute -ExcludeVariable -ExcludeAttribute

'$TestNok' | Test-VariableAndAttribute
'$TestNok' | Test-VariableAndAttribute -ExcludeVariable
'$TestNok' | Test-VariableAndAttribute -ExcludeAttribute
'$TestNok' | Test-VariableAndAttribute -ExcludeVariable -ExcludeAttribute

'$TestNok.testnok' | Test-VariableAndAttribute
'$TestNok.testnok' | Test-VariableAndAttribute -ExcludeVariable
'$TestNok.testnok' | Test-VariableAndAttribute -ExcludeAttribute
'$TestNok.testnok' | Test-VariableAndAttribute -ExcludeVariable -ExcludeAttribute

if ($Result.VariableExists -and $Result.AttributeExists) {
    "The variable and attribute chain '$Expression' exists." | Write-Output
}
elseif ($Result.VariableExists -and -not $Result.AttributeExists) {
    "The variable '$Expression' exists but the attribute chain is incomplete." | Write-Output
}
else {
    "The variable '$Expression' does not exist." | Write-Output
}
