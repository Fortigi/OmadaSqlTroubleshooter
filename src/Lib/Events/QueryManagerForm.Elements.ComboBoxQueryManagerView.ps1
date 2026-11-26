# The view (not deleted / deleted only / all) filters the list already read; no request.
$Script:QueryManagerForm.Elements.ComboBoxQueryManagerView.Add_SelectionChanged({
        try {
            Update-QueryManagerList
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
