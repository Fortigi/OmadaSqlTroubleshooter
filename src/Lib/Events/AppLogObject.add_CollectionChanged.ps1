$Script:RunTimeConfig.Logging.AppLogObject.add_CollectionChanged({
    #Do not Show-EventInfo here, it will cause a loop
    #$_ | Show-EventInfo

    try {
        Update-LogWindow
    }
    catch {
        Write-Host $_
    }
})
