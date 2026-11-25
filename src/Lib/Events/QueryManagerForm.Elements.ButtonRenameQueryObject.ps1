$Script:QueryManagerForm.Elements.ButtonRenameQueryObject.Add_Click({
        try {
            $_ | Show-EventInfo
            Invoke-QueryManagerAction -Action "Rename"
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
