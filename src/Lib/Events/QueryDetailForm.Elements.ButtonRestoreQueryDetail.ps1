$Script:QueryDetailForm.Elements.ButtonRestoreQueryDetail.Add_Click({
        try {
            $_ | Show-EventInfo
            Invoke-QueryDetailStateChange -Action "Restore"
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
