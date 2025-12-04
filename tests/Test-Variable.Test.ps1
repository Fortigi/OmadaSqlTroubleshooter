
# Description: Test-VariableAndAttribute function tests.




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

$Test = "test"


'$Global:MainForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute
'$Global:MainForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable
'$Global:MainForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeAttribute
'$Global:MainForm1.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable -ExcludeAttribute

'$Global:MainForm2.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute
'$Global:MainForm2.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable
'$Global:MainForm2.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeAttribute
'$Global:MainForm2.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable -ExcludeAttribute

'$Global:MainForm3.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute
'$Global:MainForm3.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable
'$Global:MainForm3.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeAttribute
'$Global:MainForm3.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable -ExcludeAttribute

'$Global:MainForm4.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute
'$Global:MainForm4.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable
'$Global:MainForm4.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeAttribute
'$Global:MainForm4.Elements.ButtonSaveQuery.IsEnabled' | Test-VariableAndAttribute -ExcludeVariable -ExcludeAttribute

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
