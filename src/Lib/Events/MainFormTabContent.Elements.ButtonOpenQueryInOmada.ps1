$Script:MainForm.Elements.ButtonOpenQueryInOmada.Add_Click({
        try {
            $_ | Show-EventInfo
            Open-OmadaQueryObject -DoId $Script:AppConfig.CurrentSqlQuery.DoId
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
