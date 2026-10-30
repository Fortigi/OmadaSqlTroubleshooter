function Invoke-WebViewMessage {
    <#
    .SYNOPSIS
        Acts on one message the Monaco editor posted through window.chrome.webview.postMessage.

    .DESCRIPTION
        The body of the tab's WebMessageReceived handler (Initialize-WebViewForTab), moved here so it
        can be tested without WPF and WebView2. The handler only finds the owning tab and calls this.

        'contentChanged' is handled first and returns before any logging (issue #185). The editor
        posts it on EVERY keystroke, and the event line plus two DEBUG lines that every other message
        writes cost UI-thread time per keystroke even when DEBUG is filtered out - Write-LogOutput
        resolves its call stack and tab context before it applies the level - while saying the same
        thing every time.

        Every other message is logged as before, then routed to the same action as before. Each runs
        through the dispatcher with its tab made active first: the schema, the query and the save all
        belong to the tab that asked.

    .PARAMETER TabSession
        The tab whose editor posted the message.

    .PARAMETER WebViewSender
        The CoreWebView2 that raised the event, for the log line.

    .PARAMETER MessageEventArgs
        The CoreWebView2WebMessageReceivedEventArgs.

    .PARAMETER EventInfo
        The event's $_, for Show-EventInfo.

    .OUTPUTS
        None.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession,

        [Parameter(Mandatory = $false)]
        $WebViewSender,

        [Parameter(Mandatory = $true)]
        $MessageEventArgs,

        [Parameter(Mandatory = $false)]
        $EventInfo
    )

    $Message = Get-WebViewMessageString -MessageEventArgs $MessageEventArgs
    $MessageObj = $null
    if ($Message) {
        $MessageObj = $Message | ConvertFrom-Json -ErrorAction SilentlyContinue
    }
    $Type = if ($MessageObj) { [string]$MessageObj.type } else { $null }

    if ($Type -eq 'contentChanged') {
        $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                Invoke-EditorContentChanged -TabSession $TabSession
            })
        return
    }

    if ($null -ne $EventInfo) {
        $EventInfo | Show-EventInfo
    }
    "CoreWebView2.add_WebMessageReceived on {0} for tab '{1}'" -f $WebViewSender.GetType().Name, $TabSession.DisplayName | Write-LogOutput -LogType DEBUG
    "WebView2 message received: {0}" -f $Message | Write-LogOutput -LogType DEBUG

    switch ($Type) {
        'executeQuery' {
            "Execute Query requested from Monaco Editor via {0}" -f $MessageObj.key | Write-LogOutput -LogType DEBUG
            $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                    Set-ActiveTabContext -TabSession $TabSession
                    $Script:MainForm.Elements.ButtonExecuteQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                })
        }
        'saveQuery' {
            "Save Query requested from Monaco Editor via {0}" -f $MessageObj.key | Write-LogOutput -LogType DEBUG
            $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                    Set-ActiveTabContext -TabSession $TabSession
                    $Script:MainForm.Elements.ButtonSaveQuery.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
                })
        }
        'requestSchema' {
            # Issue #158: the editor hit "[SomeDatabase]." and has no model for it. Set-ActiveTabContext
            # first, like every other branch here - the schema is fetched and cached per connection
            # pool, and the pool belongs to the tab that asked.
            "SQL schema for another database requested from Monaco Editor" | Write-LogOutput -LogType DEBUG
            $Script:MainForm.Definition.Dispatcher.Invoke([System.Action] {
                    Set-ActiveTabContext -TabSession $TabSession
                    Request-SqlSchemaForDatabase -DatabaseName $MessageObj.database
                })
        }
    }
}
