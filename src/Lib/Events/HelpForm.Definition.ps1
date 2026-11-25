# Help window events (see Open-HelpForm).

$Script:HelpForm.Elements.ButtonHelpProject.Add_Click({
        try { Open-HelpUrl -Url (Get-HelpLink -Name Project) } catch { $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_ }
    })

$Script:HelpForm.Elements.ButtonHelpGallery.Add_Click({
        try { Open-HelpUrl -Url (Get-HelpLink -Name Gallery) } catch { $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_ }
    })

$Script:HelpForm.Elements.ButtonHelpIssues.Add_Click({
        try { Open-HelpUrl -Url (Get-HelpLink -Name Issues) } catch { $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_ }
    })

$Script:HelpForm.Elements.ButtonHelpReportBug.Add_Click({
        try { Open-GitHubIssue -Kind Bug } catch { $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_ }
    })

$Script:HelpForm.Elements.ButtonHelpRequestFeature.Add_Click({
        try { Open-GitHubIssue -Kind Feature } catch { $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_ }
    })

$Script:HelpForm.Elements.ButtonCloseHelp.Add_Click({
        $Script:HelpForm.Definition.Close()
    })
