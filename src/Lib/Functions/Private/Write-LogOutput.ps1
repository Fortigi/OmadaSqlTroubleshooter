function Write-LogOutput {
    PARAM(
        [parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $True)]
        [string]$Message,
        [ValidateSet("DEBUG", "INFO", "ERROR", "VERBOSE", "WARNING", "FATAL", "LOG", "VERBOSE2")]
        [string]$LogType = "INFO",
        [switch]$SkipDialog
    )

    try {

        if ($null -eq $Message) {
            $Message = "-"
        }
        $DateTimeObject = Get-Date
        $DateTime = $DateTimeObject.ToString("yyyy-MM-dd HH:mm:ss")
        if ($Script:RunTimeConfig.Logging.LogLevelSetting -in ("VERBOSE", "VERBOSE2")) {
            $DateTime = $DateTimeObject.ToString("o")
        }

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
            Color       = "White"
        }

        $LogMessageDialog = @{
            Show        = $false
            Text        = $Message
            DialogTitle = $null
            DialogIcon  = $null
        }

        switch ($Script:RunTimeConfig.Logging.LogLevelSetting) {
            { $_ -eq "VERBOSE2" -and $LogType -in @( "DEBUG", "INFO", "ERROR", "VERBOSE", "WARNING", "FATAL", "LOG", "VERBOSE2") } {
                $LogMessage.Show = $true
                $LogMessage.Color = "Gray"
            }
            { $_ -eq "VERBOSE" -and $LogType -in @( "DEBUG", "INFO", "ERROR", "VERBOSE", "WARNING", "FATAL", "LOG") } {
                $LogMessage.Show = $true
                $LogMessage.Color = "Magenta"
            }
            { $_ -eq "DEBUG" -and $LogType -in @( "DEBUG", "INFO", "ERROR", "WARNING", "FATAL", "LOG") } {
                $LogMessage.Show = $true
                $LogMessage.Color = "Cyan"
            }
            { $_ -eq "INFO" -and $LogType -in @( "INFO", "ERROR", "WARNING", "FATAL", "LOG") } {
                $LogMessage.Show = $true
                $LogMessage.Color = "White"
            }
            { $_ -eq "WARNING" -and $LogType -in @(  "ERROR", "WARNING", "FATAL", "LOG") } {
                $LogMessage.Show = $true
                $LogMessage.Color = "Yellow"
            }
            { $_ -in @("ERROR", "FATAL") -and $LogType -in @(  "ERROR", "FATAL", "LOG") } {
                $LogMessage.Show = $true
                $LogMessage.Color = "Red"
            }
            Default {
                $LogMessage.Show = $false
            }
        }

        switch ($LogType) {
            { $_ -eq "VERBOSE2" -and $LogMessage.Show } {
                if (!$Script:RunTimeConfig.VerboseParameterSet -and $Script:RunTimeConfig.LogToConsole) {
                    $LogMessage.ShowVerbose = $true
                }
            }
            { $_ -eq "VERBOSE" -and $LogMessage.Show } {
                if (!$Script:RunTimeConfig.VerboseParameterSet -and $Script:RunTimeConfig.LogToConsole) {
                    $LogMessage.ShowVerbose = $true
                }
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
            { $_ -eq "LOG" -and $LogMessage.Show } {}
            Default {}
        }

        if ($LogMessage.Show) {
            $Script:RunTimeConfig.Logging.AppLogObject.Add(($LogMessage.Text) -join "`r`n")
            if ($Script:RunTimeConfig.LogToConsole) {
                $LogMessage.Text | Write-Host -ForegroundColor $LogMessage.Color
            }
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
                    $LogMessage.Text | Write-Host -ForegroundColor $LogMessage.Color
                }
            }
        }
        if ($LogMessage.ShowError) {
            $LogMessage.Text | Write-Error
        }
        if ($null -ne $Script:TextBoxLog -and $Script:TextBoxLog.IsLoaded) {
            if (Invoke-LogWindowScrollToEnd) {
                $Script:TextBoxLog.ScrollToEnd()
            }
        }
    }
    catch {
        $_.Exception.Message | Write-Error
    }
}
