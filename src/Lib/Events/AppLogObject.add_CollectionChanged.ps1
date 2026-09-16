$Script:RunTimeConfig.Logging.AppLogObject.add_CollectionChanged({
        #Do not Show-EventInfo here, it will cause a loop
        #$_ | Show-EventInfo

        try {
            Update-LogForm
        }
        catch {
            # Write-Host, not Write-LogOutput: that would append to AppLogObject and re-trigger this handler, looping.
            Write-Host $_
        }
    })
