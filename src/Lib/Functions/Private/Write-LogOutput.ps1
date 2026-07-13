function Write-LogOutput {
    [CmdLetBinding()]
    param(
        [parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [string]$Message,
        $ErrorObject,
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
        # Prefix every entry with the tab it originated from. Log lines emitted while a tab is active
        # carry that tab's Display name; lines emitted with no active tab (startup, shell/main-window
        # operations) are labelled "Main".
        $TabContext = "Main"
        try {
            if (![string]::IsNullOrWhiteSpace($Script:ActiveTabId)) {
                $ActiveLogTab = $Script:Tabs | Where-Object { $_.Id -eq $Script:ActiveTabId } | Select-Object -First 1
                if ($null -ne $ActiveLogTab -and ![string]::IsNullOrWhiteSpace($ActiveLogTab.DisplayName)) {
                    $TabContext = $ActiveLogTab.DisplayName
                }
            }
        }
        catch {
            $TabContext = "Main"
        }

        $LogMessage = @{
            #VERBOSE2 length = 8
            Text        = "{0} - {1}{2}- {3} - {4}: {5}" -f $DateTime, $LogType, ((0..(8 - $LogType.Length) | ForEach-Object { ' ' }) -join ''), $TabContext, $CalledFrom, $Message
            CallStack   = ($PSCallStack | Select-Object -Skip 1 -SkipLast 1 | Select-Object Location -ExpandProperty Location) -join "`n"
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
            }
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
            default {
                $LogMessage.Show = $false
            }
        }

        switch ($LogType) {
            { $_ -eq "VERBOSE2" -and $LogMessage.Show } {
                if (!$Script:RunTimeConfig.VerboseParameterSet -and $Script:RunTimeConfig.Logging.LogToConsole) {
                    $LogMessage.ShowVerbose = $true
                }
                $LogMessage.Color = "Gray"
            }
            { $_ -eq "VERBOSE" -and $LogMessage.Show } {
                if (!$Script:RunTimeConfig.VerboseParameterSet -and $Script:RunTimeConfig.Logging.LogToConsole) {
                    $LogMessage.ShowVerbose = $true
                }
                $LogMessage.Color = "Magenta"
            }
            { $_ -eq "DEBUG" -and $LogMessage.Show } {
                $LogMessage.Color = "Cyan"
            }
            { $_ -eq "INFO" -and $LogMessage.Show } {
                $LogMessage.Color = "White"
            }
            { $_ -eq "WARNING" -and $LogMessage.Show } {
                $LogMessage.ShowWarning = $true
                $LogMessageDialog.Show = $true
                $LogMessageDialog.Text = "Warning:`r`n`r`n{0}" -f $LogMessageDialog.Text
                $LogMessageDialog.Title = "Warning"
                $LogMessageDialog.Icon = [System.Windows.Forms.MessageBoxIcon]::Warning
                $LogMessage.Color = "Yellow"
                if ($null -ne $Script:PopUpWindowQueryRefresh) {
                    $Script:PopUpWindowQueryRefresh.Close()
                }
            }
            { $_ -in @("ERROR", "FATAL") -and $LogMessage.Show } {
                try {
                    $CallStack = $null # Get-PSCallStack | ConvertTo-Json -Depth 15 -ErrorAction SilentlyContinue
                    "{0}`r`n{1}" -f $LogMessage.Text, $CallStack | Write-Verbose
                }
                catch {}
                $LogMessage.ShowError = $true
                $LogMessageDialog.Show = $true
                $LogMessageDialog.Title = "Error"
                try {
                    if ($Null -ne $ErrorObject) {
                        if ($null -ne $ErrorObject.Exception?.StatusCode) {
                            $LogMessageDialog.Title += "{0} - ({1} - {2})" -f $LogMessageDialog.Title, $ErrorObject.Exception.StatusCode, $ErrorObject.Exception.Response.ReasonPhrase
                            $LogMessageDialog.Text = "Failure {0} - {1} occurred:`r`n`r`n{2}" -f $LogMessageDialog.Text, $ErrorObject.Exception.StatusCode, $ErrorObject.Exception.Response.ReasonPhrase
                        }
                    }
                    else {
                        $LogMessageDialog.Text = "Failure occurred:`r`n`r`n{0}" -f $LogMessageDialog.Text
                    }
                }
                catch {}
                $LogMessageDialog.Icon = [System.Windows.Forms.MessageBoxIcon]::Error
                $LogMessage.Color = "Red"
                if ($null -ne $Script:PopUpWindowQueryRefresh) {
                    $Script:PopUpWindowQueryRefresh.Close()
                }
            }
            { $_ -eq "LOG" -and $LogMessage.Show } {}
            default {}
        }

        if ($LogMessage.Show) {
            $Script:RunTimeConfig.Logging.AppLogObject.Add(($LogMessage.Text) -join "`r`n")
            if ($Script:RunTimeConfig.Logging.LogToConsole) {
                $LogMessage.Text | Write-Host -ForegroundColor $LogMessage.Color
            }
        }
        if ($LogMessage.ShowVerbose) {
            $LogMessage.Text | Write-Verbose
        }
        if ($LogMessageDialog.Show -and !$SkipDialog) {
            # A blocking dialog pumps this thread's messages while it's up, which can let
            # $Script:WebViewCompletionPollTimer's Tick fire reentrantly nested inside it -
            # suspend it for the duration so that can't happen (see
            # Suspend-WebViewCompletionPolling.ps1 for why).
            Suspend-WebViewCompletionPolling
            try {
                if ($null -ne $Script:MainForm -and $null -ne $Script:MainForm.Definition -and $Script:MainForm.Definition.IsVisible) {
                    $TrimmedText = Limit-MessageBoxText -Text $LogMessageDialog.Text
                    [System.Windows.Forms.MessageBox]::Show($TrimmedText, $LogMessageDialog.Title, [System.Windows.Forms.MessageBoxButtons]::OK, $LogMessageDialog.Icon)
                    Restore-MainFormFocus
                }
                else {
                    $MessageBoxImage = [System.Windows.MessageBoxImage]::Information
                    if ($LogMessage.ShowWarning) {
                        $LogMessage.Text | Write-Warning
                        $MessageBoxImage = [System.Windows.MessageBoxImage]::Warning
                    }
                    elseif ($LogMessage.ShowError) {
                        $LogMessage.Text, $LogMessage.CallStack -join ", `n" | Write-Error
                        $MessageBoxImage = [System.Windows.MessageBoxImage]::Error
                    }
                    else {
                        $LogMessage.Text | Write-Host -ForegroundColor $LogMessage.Color
                    }
                    [System.Windows.MessageBox]::Show((Limit-MessageBoxText -Text $LogMessageDialog.Text), $LogMessageDialog.Title, [System.Windows.MessageBoxButton]::OK, $MessageBoxImage) | Out-Null
                }
            }
            finally {
                Resume-WebViewCompletionPolling
            }
        }
        if ($LogMessage.ShowError) {
            $LogMessage.Text, $LogMessage.CallStack -join ", `n" | Write-Error
        }
        if ($null -ne $Script:TextBoxLog -and $Script:TextBoxLog.IsLoaded) {
            if (Invoke-LogFormScrollToEnd) {
                $Script:TextBoxLog.ScrollToEnd()
            }
        }
    }
    catch {
        $_.Exception.Message | Write-Error
    }
}
