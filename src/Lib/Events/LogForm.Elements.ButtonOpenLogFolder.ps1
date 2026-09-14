$Script:LogForm.Elements.ButtonOpenLogFolder.Add_Click({
        $_ | Show-EventInfo

        # The folder this session is actually writing to, read from the live state rather than
        # recomputed from the configuration - a session whose configured folder could not be used is
        # writing somewhere else, or nowhere, and opening the folder it failed to use would be a
        # small lie told at the worst moment.
        if ($null -eq $Script:SessionLogFile -or [string]::IsNullOrWhiteSpace($Script:SessionLogFile.Directory)) {
            "No session log file is being written, so there is no folder to open." | Write-LogOutput -LogType WARNING -SkipDialog
            return
        }

        $LogFolder = $Script:SessionLogFile.Directory
        if (-not (Test-Path -LiteralPath $LogFolder -PathType Container)) {
            "The session log folder '{0}' no longer exists." -f $LogFolder | Write-LogOutput -LogType WARNING -SkipDialog
            return
        }

        try {
            # explorer.exe rather than Start-Process on the path itself: the folder is opened with
            # the current session's file selected, which is the file the user came here for.
            if (![string]::IsNullOrWhiteSpace($Script:SessionLogFile.Path) -and (Test-Path -LiteralPath $Script:SessionLogFile.Path -PathType Leaf)) {
                Start-Process -FilePath "explorer.exe" -ArgumentList ("/select,`"{0}`"" -f $Script:SessionLogFile.Path)
            }
            else {
                Start-Process -FilePath "explorer.exe" -ArgumentList ("`"{0}`"" -f $LogFolder)
            }

            "Opened the session log folder: {0}" -f $LogFolder | Write-LogOutput -LogType DEBUG
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
