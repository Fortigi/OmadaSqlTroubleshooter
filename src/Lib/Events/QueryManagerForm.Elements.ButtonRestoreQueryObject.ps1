$Script:QueryManagerForm.Elements.ButtonRestoreQueryObject.Add_Click({
        try {
            $_ | Show-EventInfo
            Invoke-QueryManagerAction -Action "Restore"
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
