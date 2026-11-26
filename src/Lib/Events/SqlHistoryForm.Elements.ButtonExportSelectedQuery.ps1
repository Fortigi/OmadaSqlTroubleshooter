$Script:SqlHistoryForm.Elements.ButtonExportSelectedQuery.Add_Click({
        try {
            $_ | Show-EventInfo
            $null = Export-SqlHistorySelection -Kind Query
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
