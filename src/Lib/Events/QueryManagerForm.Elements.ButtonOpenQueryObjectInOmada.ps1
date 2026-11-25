$Script:QueryManagerForm.Elements.ButtonOpenQueryObjectInOmada.Add_Click({
        try {
            $_ | Show-EventInfo
            Invoke-QueryManagerAction -Action "Omada"
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
