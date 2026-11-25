$Script:QueryManagerForm.Elements.ButtonShowQueryObjectDetails.Add_Click({
        try {
            $_ | Show-EventInfo
            Invoke-QueryManagerAction -Action "Details"
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
