$Script:QueryDetailForm.Elements.ButtonOpenQueryDetailOData.Add_Click({
        try {
            $_ | Show-EventInfo
            Open-OmadaQueryObject -DoId $Script:QueryDetailForm.Query.DoId -Kind OData
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
