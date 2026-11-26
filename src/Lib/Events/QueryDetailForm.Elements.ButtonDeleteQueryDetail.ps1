$Script:QueryDetailForm.Elements.ButtonDeleteQueryDetail.Add_Click({
        try {
            $_ | Show-EventInfo
            Invoke-QueryDetailStateChange -Action "Delete"
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
