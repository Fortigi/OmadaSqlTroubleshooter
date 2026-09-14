function Write-LogOutput {
    [CmdLetBinding()]
    param(
        [parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [string]$Message,
        $ErrorObject,
        [ValidateSet("DEBUG", "INFO", "ERROR", "VERBOSE", "WARNING", "FATAL", "LOG", "VERBOSE2")]
        [string]$LogType = "INFO",
        [switch]$SkipDialog,
        # The message belongs to one tab - a query result, a failed execute - rather than to the
        # application. Since queries run in the background (issue #40) such a message can arrive for a
        # tab the user is not looking at, and a modal about an invisible query interrupts whatever
        # they are doing on the tab they ARE looking at. A tab-scoped message raised while its tab is
        # off screen is therefore held and shown when that tab is next opened.
        #
        # Opt-in, so everything that has not been considered keeps today's behaviour: an application
        # failure is not about a tab and must be seen wherever the user is.
        [switch]$TabScoped
    )

    try {

        if ($null -eq $Message) {
            $Message = "-"
        }

        # Last gate before anything reaches AppLogObject, which the log window's "Export Log File"
        # button writes to disk verbatim. Structure-aware redaction already happened at the call
        # sites via ConvertTo-RedactedLogString; this catches secrets embedded in free-form text -
        # exception messages, third-party output, and any call site that forgets. Applied to
        # $Message itself so every derived value (the log line, the dialog text, the Write-Error
        # and Write-Verbose paths) inherits it.
        $Message = Protect-LogMessage -Message $Message

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

        # The Messages pane's own copy of the text, kept separate from $LogMessageDialog.Text
        # (issue #128). The heading and two leading blank lines the WARNING/ERROR branches below
        # add exist to separate a modal dialog's summary from its detail; the pane is not a
        # dialog - it is a durable, top-aligned text surface beside the results, and the status
        # bar (issue #117) already names the outcome, so the pane gets the plain message with
        # nothing prepended. Application-level dialogs (Show-LogMessageDialog and the no-window
        # MessageBox path below) keep reading $LogMessageDialog.Text and are unaffected by this.
        $LogMessagePaneText = $Message

        # The same inclusion table this switch statement always applied, moved into
        # Test-LogLevelThreshold. There are two levels that filter now - the log window's, here, and
        # the session log file's own (issue #121), which may reasonably be more verbose - and two
        # copies of the table would drift.
        $LogMessage.Show = Test-LogLevelThreshold -Level $Script:RunTimeConfig.Logging.LogLevelSetting -LogType $LogType

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
                # Named after the tab it came from. With several tabs open - and queries now running
                # in the background, so a message can arrive for a tab the user is not looking at -
                # "Warning" alone does not say which query is being complained about.
                $LogMessageDialog.Title = "Warning - {0}" -f $TabContext
                $LogMessageDialog.Icon = [System.Windows.Forms.MessageBoxIcon]::Warning
                $LogMessage.Color = "Yellow"
            }
            { $_ -in @("ERROR", "FATAL") -and $LogMessage.Show } {
                try {
                    $CallStack = $null # Get-PSCallStack | ConvertTo-Json -Depth 15 -ErrorAction SilentlyContinue
                    "{0}`r`n{1}" -f $LogMessage.Text, $CallStack | Write-Verbose
                }
                catch {}
                $LogMessage.ShowError = $true
                $LogMessageDialog.Show = $true
                # Named after the tab it came from - see the Warning branch above for why.
                $LogMessageDialog.Title = "Error - {0}" -f $TabContext
                try {
                    if ($Null -ne $ErrorObject) {
                        if ($null -ne $ErrorObject.Exception?.StatusCode) {
                            # Assignment, not "+=". The format string's {0} is the title itself, so
                            # appending it produced the title twice:
                            #   "Error - Mve: queryError - Mve: query - (500 - Internal Server Error)"
                            $LogMessageDialog.Title = "{0} - ({1} - {2})" -f $LogMessageDialog.Title, $ErrorObject.Exception.StatusCode, $ErrorObject.Exception.Response.ReasonPhrase

                            # Argument order. These three were passed message-first, so the user's
                            # actual error landed in the status-code slot and the reason phrase
                            # replaced the message body:
                            #   "Failure The query pipeline failed - 500 occurred:
                            #
                            #    Internal Server Error"
                            $LogMessageDialog.Text = "Failure {0} - {1} occurred:`r`n`r`n{2}" -f $ErrorObject.Exception.StatusCode, $ErrorObject.Exception.Response.ReasonPhrase, $LogMessageDialog.Text

                            # The dialog Title carries the status code too, but a tab-scoped failure
                            # (issue #93) never raises a dialog, so the Title is never shown to a tab
                            # user. Without this the status code would vanish entirely from what a tab
                            # user sees once the pane heading above is dropped - append it as plain
                            # trailing detail instead, with no heading and no blank lines.
                            $LogMessagePaneText = "{0} ({1} - {2})" -f $LogMessagePaneText, $ErrorObject.Exception.StatusCode, $ErrorObject.Exception.Response.ReasonPhrase
                        }
                    }
                    else {
                        $LogMessageDialog.Text = "Failure occurred:`r`n`r`n{0}" -f $LogMessageDialog.Text
                    }
                }
                catch {}
                $LogMessageDialog.Icon = [System.Windows.Forms.MessageBoxIcon]::Error
                $LogMessage.Color = "Red"
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

        # The same finished line to this session's log file (issue #121). BEHIND Protect-LogMessage,
        # never beside it: a file outlives the process, gets backed up and gets attached to support
        # tickets, so a writer that took its own copy of $Message would put unredacted credentials,
        # tokens, result data and query text on disk permanently - a regression of #39 and #111 and
        # strictly worse than the problem the file exists to solve. $LogMessage.Text is the masked
        # text, the same string AppLogObject receives above.
        #
        # Outside the $LogMessage.Show block on purpose. Show is the LOG WINDOW's decision; the file
        # has a level of its own, which is usually the more verbose of the two - that is what removes
        # the "please reproduce it with -LogLevel VERBOSE" round trip. Write-SessionLogFile applies
        # it, and does nothing at all when no file is being written.
        Write-SessionLogFile -Line (($LogMessage.Text) -join "`r`n") -LogType $LogType
        if ($LogMessage.ShowVerbose) {
            $LogMessage.Text | Write-Verbose
        }
        if ($LogMessageDialog.Show -and !$SkipDialog) {
            if ($null -ne $Script:MainForm -and $null -ne $Script:MainForm.Definition -and $Script:MainForm.Definition.IsVisible) {
                # A message that belongs to a tab goes to that tab's Messages pane and raises no
                # dialog at all (issue #93). A modal stopped the user, had to be dismissed before they
                # could look at the query that caused it, and was gone once dismissed; the pane keeps
                # the text beside the SQL that produced it, selectable and copyable.
                #
                # Nothing needs holding any more either. The pane IS per tab and durable, so a failure
                # raised while its tab is off screen is simply waiting there when the user opens it -
                # which is what Add-TabScopedMessage's queue existed to simulate.
                #
                # An application-level failure is not tab-scoped and still interrupts: it is not about
                # a tab, the user may have no tab open, and it must be seen wherever they are.
                #
                # Focus follows severity here, and only severity. An ERROR pulls the pane to the front
                # because a failure the user cannot see is the thing this issue set out to fix. A
                # WARNING does not, because a warning on its own is not a reason to take the user off
                # whatever they were looking at.
                #
                # Severity is the right rule for a message that arrives on its own, and the wrong one
                # for the end of an execute: the commonest WARNING by far is "Query did not return any
                # results", which is a completed execute with nothing to show, and severity cannot
                # tell it apart from one that returned rows. That decision therefore no longer lives
                # here - Complete-ExecuteQueryResult makes it from the outcome (issue #115), which
                # refines the issue #93 rule "on success Results stays selected" to the case it was
                # written for, a query that actually returned rows to land on.
                if ($TabScoped) {
                    Add-TabMessage -TabSession (Get-ActiveTabSession) -Text $LogMessagePaneText -Focus:$LogMessage.ShowError
                }
                else {
                    Show-LogMessageDialog -Text $LogMessageDialog.Text -Title $LogMessageDialog.Title -Icon $LogMessageDialog.Icon
                }
            }
            else {
                # No main window yet - startup, shutdown, or a console host. Nothing is tab-scoped
                # here because there are no tabs to scope to, so this path is unchanged.
                #
                # A blocking dialog pumps this thread's messages while it's up, which can let
                # $Script:WebViewCompletionPollTimer's Tick fire reentrantly nested inside it -
                # suspend it for the duration so that can't happen (see
                # Suspend-WebViewCompletionPolling.ps1 for why).
                Suspend-WebViewCompletionPolling
                try {
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
                finally {
                    Resume-WebViewCompletionPolling
                }
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
