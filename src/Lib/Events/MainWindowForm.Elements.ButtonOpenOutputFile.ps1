$Script:MainWindowForm.Elements.ButtonOpenOutputFile.Add_Click({
    $_ | Show-EventInfo
    "Open outputfile: {0}" -f $Script:RunTimeConfig.OutputFileName | Write-LogOutput
    & $Script:RunTimeConfig.OutputFileName
})
