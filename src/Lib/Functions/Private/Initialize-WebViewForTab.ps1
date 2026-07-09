function Initialize-WebViewForTab {
    <#
    .SYNOPSIS
    Sets up the WebView2/Monaco editor for one tab: resolves the WebView2 runtime, creates (or
    reuses) the shared CoreWebView2Environment, loads Monaco, and wires the editor's keyboard
    shortcuts and web-message handlers. Factored out of the single global setup that used to run
    once in MainForm.Definition.ps1's Add_Loaded, so it can run once per tab instead.

    .NOTES
    Every closure below explicitly captures $TabSession (via GetNewClosure()) and calls
    Set-ActiveTabContext at the top - these callbacks are asynchronous and may fire well after
    the user has switched to a different tab, so they must never rely on whichever tab happens
    to be "current" when they actually run.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        $TabSession.WebView.Object = $TabSession.Elements.webView21
        if ($null -eq $TabSession.WebView.Object) {
            "Failed to find WebView2 control for tab '{0}'." -f $TabSession.DisplayName | Write-LogOutput -LogType ERROR
            return
        }

        $SharedUserDataFolder = Join-Path $Env:TEMP -ChildPath "OmadaSqlTroubleshooter"
        if (-not (Test-Path -Path $SharedUserDataFolder)) {
            New-Item -Path $SharedUserDataFolder -ItemType Directory -Force | Out-Null
        }
        $TabSession.WebView.UserDataFolder = $SharedUserDataFolder

        $TabSession.WebView.EdgeWebview2RuntimePath = Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "bin\Webview2Runtime"
        if (!(Test-Path ($TabSession.WebView.EdgeWebview2RuntimePath) -PathType Container)) {
            $TabSession.WebView.EdgeWebview2RuntimePath = Join-Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)) -ChildPath "OmadaSqlTroubleShooter\bin\Webview2Runtime"
        }

        # The Monaco WebView2 only ever hosts the local editor HTML (never Omada auth), so one
        # shared CoreWebView2Environment/profile across all tabs is correct - no reason to pay
        # for N separate environments the way Omada's own auth WebView2 does.
        if ($null -eq $Script:SharedWebViewEnvironment) {
            if ((Test-Path -Path $TabSession.WebView.EdgeWebview2RuntimePath -PathType Container) -and (Test-Path -Path (Join-Path $TabSession.WebView.EdgeWebview2RuntimePath -ChildPath "msedgewebview2.exe") -PathType Leaf)) {
                $Script:SharedWebViewEnvironment = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($TabSession.WebView.EdgeWebview2RuntimePath, $SharedUserDataFolder).GetAwaiter().GetResult()
            }
            else {
                $Script:SharedWebViewEnvironment = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $SharedUserDataFolder).GetAwaiter().GetResult()
            }
        }
        $TabSession.WebView.Environment = $Script:SharedWebViewEnvironment

        if (-not (Test-Path $Script:WebView2UserProfilePath -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $Script:WebView2UserProfilePath | Out-Null
        }

        $TabSession.WebView.Object.EnsureCoreWebView2Async($TabSession.WebView.Environment).GetAwaiter().OnCompleted({
                try {
                    Set-ActiveTabContext -TabSession $TabSession
                    "EnsureCoreWebView2Async OnCompleted script for tab '{0}'" -f $TabSession.DisplayName | Write-LogOutput -LogType DEBUG

                    if ($null -eq $TabSession.WebView.Object.CoreWebView2) {
                        $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                                $Message = "WebView2 environment initialization failed. If this system does not have the Webview2 Runtime installed, please download the fixed version from https://developer.microsoft.com/en-us/microsoft-edge/webview2/ and extract the cab file to folder '{0}'" -f $TabSession.WebView.EdgeWebview2RuntimePath
                                $Message | Write-LogOutput -LogType ERROR
                            })
                        return
                    }

                    $HtmlFile = Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "Monaco\index.html"
                    if ([System.IO.File]::Exists($HtmlFile)) {
                        $TabSession.WebView.Object.Dispatcher.Invoke([System.Action] {
                                $TabSession.WebView.Object.Source = New-Object System.Uri($HtmlFile)
                                "WebView source set to: {0}" -f $HtmlFile | Write-LogOutput -LogType DEBUG
                            })
                    }
                    else {
                        $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                                "Monaco HTML file not found at: {0}" -f $HtmlFile | Write-LogOutput -LogType ERROR
                            })
                    }

                    Test-ConnectionButton
                    Update-QueryList
                    Set-EditorValue

                    $TabSession.WebView.Object.add_PreviewKeyDown({
                            param($EventSender, $EventArgs)
                            try {
                                $_ | Show-EventInfo

                                if ($EventArgs.Key -eq [System.Windows.Input.Key]::S -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
                                    "Ctrl+S key intercepted in WebView2 (PreviewKeyDown) for tab '{0}'" -f $TabSession.DisplayName | Write-LogOutput -LogType DEBUG
                                    $EventArgs.Handled = $true

                                    $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                                            Set-ActiveTabContext -TabSession $TabSession
                                            "Triggering Save Query from Ctrl+S key press" | Write-LogOutput -LogType DEBUG
                                            $Script:MainForm.Elements.ButtonSaveQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                                        })
                                }
                            }
                            catch {
                                $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                            }
                        }.GetNewClosure())

                    $TabSession.WebView.Object.CoreWebView2.add_WebMessageReceived({
                            param($EventSender, $EventArgs)
                            try {
                                $_ | Show-EventInfo
                                "CoreWebView2.add_WebMessageReceived for tab '{0}'" -f $TabSession.DisplayName | Write-LogOutput -LogType DEBUG

                                $Message = $EventArgs.TryGetWebMessageAsString()
                                "WebView2 message received: {0}" -f $Message | Write-LogOutput -LogType DEBUG

                                if ($Message) {
                                    $MessageObj = $Message | ConvertFrom-Json -ErrorAction SilentlyContinue
                                    if ($MessageObj -and $MessageObj.type -eq 'executeQuery') {
                                        "Execute Query requested from Monaco Editor via {0}" -f $MessageObj.key | Write-LogOutput -LogType DEBUG
                                        $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                                                Set-ActiveTabContext -TabSession $TabSession
                                                $Script:MainForm.Elements.ButtonExecuteQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                                            })
                                    }
                                    elseif ($MessageObj -and $MessageObj.type -eq 'saveQuery') {
                                        "Save Query requested from Monaco Editor via {0}" -f $MessageObj.key | Write-LogOutput -LogType DEBUG
                                        $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                                                Set-ActiveTabContext -TabSession $TabSession
                                                $Script:MainForm.Elements.ButtonSaveQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                                            })
                                    }
                                    elseif ($MessageObj -and $MessageObj.type -eq 'contentChanged') {
                                        $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                                                $TabSession.IsDirty = $true
                                                Update-TabHeaderTitle -TabSession $TabSession
                                            })
                                    }
                                }
                            }
                            catch {
                                $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                            }
                        }.GetNewClosure())

                    $TabSession.WebView.Object.add_NavigationCompleted({
                            try {
                                $_ | Show-EventInfo
                                "Set-EditorValue after loading html for tab '{0}'" -f $TabSession.DisplayName | Write-LogOutput -LogType DEBUG
                                Set-ActiveTabContext -TabSession $TabSession
                                Set-EditorValue
                                $Script:RunTimeConfig.ReconnectStatus = 3
                            }
                            catch {
                                $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                            }
                        }.GetNewClosure())

                    "WebView2 for tab '{0}' initialized" -f $TabSession.DisplayName | Write-LogOutput -LogType DEBUG
                }
                catch {
                    "WebView2 initialization failed for tab '{0}': {1}" -f $TabSession.DisplayName, $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
                finally {
                    # Never leave the app's "current tab" globals pointed at a tab the user is no
                    # longer looking at, just because its async WebView2 setup finished last.
                    $CurrentlyActive = Get-ActiveTabSession
                    if ($null -ne $CurrentlyActive) {
                        Set-ActiveTabContext -TabSession $CurrentlyActive
                    }
                }
            }.GetNewClosure())
    }
    catch {
        "WebView2 initialization failed for tab '{0}': {1}" -f $TabSession.DisplayName, $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
