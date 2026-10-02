$Script:MainForm.Elements.ButtonSaveOutputFile.Add_Click({
        try {
            $_ | Show-EventInfo
            # The focused result (issue #151), NOT $Script:RunTimeData.QueryResult - that holds only
            # the first statement's response, so with several results stacked Save output would
            # silently write the top one whichever grid the user was working in. Its sibling
            # ButtonShowOutput was rebound and this was missed; a reviewer caught it.
            $Private:FocusedResult = Get-FocusedQueryResult
            Save-QueryResultToFile -QueryResult $Private:FocusedResult.QueryResult
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })

#    $Script:MainForm.Elements.ButtonSaveOutputFileText.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonSaveOutputFile"
#    }))

#$Script:MainForm.Elements.ButtonSaveOutputFileImage.Add_MouseLeftButtonDown({
#        Invoke-ButtonClick -ButtonName "ButtonSaveOutputFile"
#    }))
