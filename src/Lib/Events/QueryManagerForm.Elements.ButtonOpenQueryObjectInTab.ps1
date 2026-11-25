$Script:QueryManagerForm.Elements.ButtonOpenQueryObjectInTab.Add_Click({
        try {
            $_ | Show-EventInfo
            Invoke-QueryManagerAction -Action "OpenInTab"
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
