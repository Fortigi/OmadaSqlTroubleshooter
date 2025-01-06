
# Description: Test-VariableAndAttribute function tests.




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

$Test = "test"


'$Global:MainWindowForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute
'$Global:MainWindowForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable
'$Global:MainWindowForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeAttribute
'$Global:MainWindowForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable -ExcludeAttribute

'$Global:MainWindowForm2.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute
'$Global:MainWindowForm2.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable
'$Global:MainWindowForm2.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeAttribute
'$Global:MainWindowForm2.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable -ExcludeAttribute

'$Global:MainWindowForm3.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute
'$Global:MainWindowForm3.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable
'$Global:MainWindowForm3.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeAttribute
'$Global:MainWindowForm3.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable -ExcludeAttribute

'$Global:MainWindowForm4.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute
'$Global:MainWindowForm4.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable
'$Global:MainWindowForm4.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeAttribute
'$Global:MainWindowForm4.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable -ExcludeAttribute

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
