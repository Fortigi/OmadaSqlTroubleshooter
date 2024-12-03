$Script:MainWindowForm.Elements.CheckboxMyQueries.Add_Unchecked({
    $_ | Show-EventInfo
    $False | Invoke-ProcessConfigSettings -Property "MyQueriesOnly"
    $null | Invoke-ProcessConfigSettings -Property "IdentityUserName"
    Update-QueryList -ForceRefresh
})
