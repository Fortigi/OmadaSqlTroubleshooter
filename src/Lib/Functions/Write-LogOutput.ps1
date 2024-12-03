function Write-LogOutput {

    param(
        [parameter(Mandatory = $True, Position = 0, ValueFromPipeline = $True)]
        [string]$Message,
        [ValidateSet("DEBUG", "INFO", "ERROR", "VERBOSE", "WARNING", "FATAL", "LOG")]
        [string]$LogType = "INFO",
        [switch]$SkipDialog
    )

    try {

        $DateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $PSCallStack = Get-PSCallStack
        try {
            $Command = $null
            $Command = $PSCallStack[1]
            if ([string]::IsNullOrWhiteSpace($Command.Command)) {
            (Get-PSCallStack) | ForEach-Object {
                    if ([string]::IsNullOrWhiteSpace($Command.Command) -and $_.Command -ne $MyInvocation.MyCommand -and ![string]::IsNullOrWhiteSpace($_.Command)) {
                        $Command = $_
                    }
                }
            }
            $CalledFrom = "{0} ({1})" -f $Command.Command, $Command.ScriptLineNumber
        }
        catch {
            $CalledFrom = $null
        }
        $LogMessage = @{
            Text        = "{0} - {1} - {2}: {3}" -f $DateTime, $LogType, $CalledFrom, $Message
            Show        = $false
            ShowWarning = $false
            ShowError   = $false
            ShowVerbose = $false
        }

        $LogMessageDialog = @{
            Show        = $false
            Text        = $Message
            DialogTitle = $null
            DialogIcon  = $null
        }

        switch ($Script:LogLevelSetting) {
            { $_ -eq "VERBOSE" -and $LogType -in @( "DEBUG", "INFO", "ERROR", "VERBOSE", "WARNING", "FATAL", "LOG") } {
                $LogMessage.Show = $true
            }
            { $_ -eq "DEBUG" -and $LogType -in @( "DEBUG", "INFO", "ERROR", "WARNING", "FATAL", "LOG") } {
                $LogMessage.Show = $true
            }
            { $_ -eq "INFO" -and $LogType -in @( "INFO", "ERROR", "WARNING", "FATAL", "LOG") } {
                $LogMessage.Show = $true
            }
            { $_ -eq "WARNING" -and $LogType -in @(  "ERROR", "WARNING", "FATAL", "LOG") } {
                $LogMessage.Show = $true
            }
            { $_ -in @("ERROR", "FATAL") -and $LogType -in @(  "ERROR", "FATAL", "LOG") } {
                $LogMessage.Show = $true
            }
            Default {
                $LogMessage.Show = $false
            }
        }

        switch ($LogType) {
            { $_ -eq "VERBOSE" -and $LogMessage.Show } {
                $LogMessage.ShowVerbose = $true
            }
            { $_ -eq "DEBUG" -and $LogMessage.Show } {}
            { $_ -eq "INFO" -and $LogMessage.Show } {}
            { $_ -eq "WARNING" -and $LogMessage.Show } {
                $LogMessage.ShowWarning = $true
                $LogMessageDialog.Show = $true
                $LogMessageDialog.Text = "Warning:`r`n`r`n{0}" -f $LogMessageDialog.Text
                $LogMessageDialog.Title = "Warning"
                $LogMessageDialog.Icon = [System.Windows.Forms.MessageBoxIcon]::Warning
            }
            { $_ -in @("ERROR", "FATAL") -and $LogMessage.Show } {
                try {
                    $CallStack = $null # Get-PSCallStack | ConvertTo-Json -Depth 15 -ErrorAction SilentlyContinue
                    "{0}`r`n{1}" -f $LogMessage.Text, $CallStack | Write-Verbose
                }
                catch {}
                $LogMessage.ShowError = $true
                $LogMessageDialog.Show = $true
                $LogMessageDialog.Text = "Failure occurred:`r`n`r`n{0}" -f $LogMessageDialog.Text
                $LogMessageDialog.Title = "Error"
                $LogMessageDialog.Icon = [System.Windows.Forms.MessageBoxIcon]::Error
            }
            Default {}
        }

        if ($LogMessage.Show) {
            $AppLogObject.Add(($LogMessage.Text) -join "`r`n")
        }
        if ($LogMessage.ShowVerbose) {
            $LogMessage.Text | Write-Verbose
        }
        if ($LogMessageDialog.Show -and !$SkipDialog) {
            if ($null -ne $Script:MainWindowForm -and $null -ne $Script:MainWindowForm.Definition -and $Script:MainWindowForm.Definition.IsVisible) {
                [System.Windows.Forms.MessageBox]::Show($LogMessageDialog.Text, $LogMessageDialog.Title, [System.Windows.Forms.MessageBoxButtons]::OK, $LogMessageDialog.Icon)
            }
            else {
                if ($LogMessage.ShowWarning) {
                    $LogMessage.Text | Write-Warning
                }
                elseif ($LogMessage.ShowError) {
                    $LogMessage.Text | Write-Error
                }
                else {
                    $LogMessage.Text | Write-Host
                }
            }
        }
        if ($LogMessage.ShowError) {
            $LogMessage.Text | Write-Error
        }
        if ($null -ne $Script:TextBoxLog) {
            if (Invoke-LogWindowScrollToEnd) {
                $Script:TextBoxLog.ScrollToEnd()
            }
        }
    }
    catch {
        $_.Exception.Message | Write-Error
    }
}
