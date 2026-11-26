$Script:SqlHistoryForm.Elements.ButtonExportSelectedDiff.Add_Click({
        try {
            $_ | Show-EventInfo
            $null = Export-SqlHistorySelection -Kind Diff
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
