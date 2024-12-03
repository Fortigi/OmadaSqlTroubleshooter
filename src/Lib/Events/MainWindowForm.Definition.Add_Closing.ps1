$Script:MainWindowForm.Definition.Add_Closing({
    $_ | Show-EventInfo
    Save-WindowMeasurements
})
