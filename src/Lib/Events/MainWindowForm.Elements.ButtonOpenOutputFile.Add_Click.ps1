$Script:MainWindowForm.Elements.ButtonOpenOutputFile.Add_Click({
    $_ | Show-EventInfo
    "Open outputfile: {0}" -f $Script:OutputFileName | Write-LogOutput
    & $Script:OutputFileName
})
