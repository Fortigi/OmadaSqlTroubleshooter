$Script:QueryManagerForm.Elements.ButtonDeleteQueryObject.Add_Click({
        try {
            $_ | Show-EventInfo
            Invoke-QueryManagerAction -Action "Delete"
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
