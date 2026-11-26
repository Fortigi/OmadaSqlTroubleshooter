$Script:QueryManagerForm.Elements.ButtonOpenQueryObjectOData.Add_Click({
        try {
            $_ | Show-EventInfo
            Invoke-QueryManagerAction -Action "OData"
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
