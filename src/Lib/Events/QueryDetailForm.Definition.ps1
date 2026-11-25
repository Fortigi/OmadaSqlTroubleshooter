# Query detail window events (see Open-QueryDetailForm).

$Script:QueryDetailForm.Elements.ButtonRenameQueryDetail.Add_Click({
        try {
            $_ | Show-EventInfo
            $Private:Query = $Script:QueryDetailForm.Query
            if ($null -ne (Rename-SqlQuery -DoId $Private:Query.DoId -DisplayName $Private:Query.DisplayName)) {
                Update-QueryDetailForm
            }
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })

$Script:QueryDetailForm.Elements.ButtonOpenQueryDetail.Add_Click({
        try {
            $_ | Show-EventInfo
            Invoke-QueryDetailOpen -InPlace
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })

$Script:QueryDetailForm.Elements.ButtonOpenQueryDetailInTab.Add_Click({
        try {
            $_ | Show-EventInfo
            Invoke-QueryDetailOpen
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })

$Script:QueryDetailForm.Elements.ButtonShowQueryDetailHistory.Add_Click({
        try {
            $_ | Show-EventInfo
            $Private:Query = $Script:QueryDetailForm.Query
            Open-SqlHistoryForm -DoId $Private:Query.DoId -QueryName $Private:Query.DisplayName -Owner $Script:QueryDetailForm.Definition

            # A version restored there opened its tab and asked the manager to close.
            if (-not (Complete-QueryManagerChildWindow -Window $Script:QueryDetailForm.Definition)) {
                Update-QueryDetailForm
            }
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })

$Script:QueryDetailForm.Elements.ButtonOpenQueryDetailInOmada.Add_Click({
        try {
            $_ | Show-EventInfo
            Open-OmadaQueryObject -DoId $Script:QueryDetailForm.Query.DoId
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })

$Script:QueryDetailForm.Elements.ButtonCloseQueryDetail.Add_Click({
        $Script:QueryDetailForm.Definition.Close()
    })
