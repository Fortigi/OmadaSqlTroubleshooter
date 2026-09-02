function Invoke-OmadaPSWebRequestWrapper {
    [CmdLetBinding()]
    param()

    $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

    # Invoke-OmadaRestMethod (OmadaWeb.PS) can show its own interactive WebView2/Browser login
    # popup when authentication is needed - a modal window this app does not own, but which pumps
    # this thread's messages while blocked exactly like our own dialogs (see
    # Suspend-WebViewCompletionPolling.ps1). Without suspending here, the WebViewCompletionPollTimer
    # can fire reentrantly during that popup and process a DIFFERENT tab's WebView2 completion,
    # repointing $Script:MainForm.Elements/$Script:AppConfig/etc. mid-call - corrupting which tab's
    # UI this function's own status updates (and any Set-SqlConnectionState a caller makes right
    # after it returns) end up applying to. This is the single choke point every Omada REST call in
    # this app goes through, so suspending here covers all of them.
    Suspend-WebViewCompletionPolling
    try {
        if (!$Script:RunTimeData.SkipRetryRequest) {
            $Private:Parameters = $Script:RunTimeData.RestMethodParam
            #$Private:Parameters.AuthenticationType = $($Script:MainForm.Elements.ComboBoxSelectAuthenticationOption.SelectedItem.Content)
            $Private:Parameters.UseWebView2 = $Private:Parameters.AuthenticationType -eq "Browser" ? $($Script:RunTimeConfig.UseWebView2Auth) : $false
            if ($null -eq $Private:Parameters.Body) {
                if ($Private:Parameters.ContainsKey("Body")) {
                    $Private:Parameters.Remove("Body")
                }
            }
            else {
                if (!$Private:Parameters.ContainsKey("Body")) {
                    $Private:Parameters.Add("Body", $null)
                }

                #$Private:Parameters.Body = $Private:Parameters.Body | ConvertTo-Json
            }

            # Keep the module's own verbose stream in step with this application's log, so the two
            # do not contradict each other on the same request. Passed only when the installed
            # OmadaWeb.PS actually declares the parameter: -SkipBodyRedaction is newer than the
            # pinned minimum version, and splatting a parameter a cmdlet does not have is a
            # terminating error. Capability-checked rather than version-gated, so this works the day
            # the switch ships without forcing everyone onto a release that does not exist yet.
            $Private:RestMethodCommand = Get-Command -Name Invoke-OmadaRestMethod -ErrorAction SilentlyContinue
            if ($null -ne $Private:RestMethodCommand -and $Private:RestMethodCommand.Parameters.ContainsKey("SkipBodyRedaction")) {
                $Private:Parameters.SkipBodyRedaction = [bool]$Script:SkipBodyRedaction
            }
            elseif ($Private:Parameters.ContainsKey("SkipBodyRedaction")) {
                # The installed module was downgraded mid-session; drop the key rather than fail.
                $Private:Parameters.Remove("SkipBodyRedaction")
            }

            "Parameters: {0}" -f (ConvertTo-RedactedLogString -InputObject $Private:Parameters) | Write-LogOutput -LogType VERBOSE
            $Private:Result = Invoke-OmadaRestMethod @Parameters
            # Deliberately no status-bar write here. A successful request is not the same thing as a
            # connected tab: this transport is also used by probes and by work that runs while a tab
            # is being connected, so writing "Connected" from here put the status bar ahead of - and
            # sometimes in contradiction with - the rest of the UI, which is all derived from
            # $Script:ConnectionStatus (Test-ConnectionButton for the button text,
            # Set-SqlQueryFunctionState for the dropdowns and Display name). Connection state is
            # single-sourced: Set-SqlConnectionState is the only writer of both the flag and the
            # status bar text.
            "Result: {0}" -f (ConvertTo-RedactedLogString -InputObject $Private:Result) | Write-LogOutput -LogType VERBOSE
            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false
            return $Private:Result
        }
        else {
            return $null
        }
    }
    catch {
        if (![string]::IsNullOrWhiteSpace($_.ErrorDetails?.Message) -and $_.ErrorDetails.Message -like "*Resource not found for the segment 'C_P_SQLTROUBLESHOOTING'*") {
            $Message = "OData Endpoint for SQL Troubleshooting not enabled at tenant {0}.`n`r`n`rError returned by Omada:`n`r`n`r{1}" -f [system.uri]::New($Script:AppConfig.BaseUrl).Host, $_.ErrorDetails.Message
            # Route the teardown through the state function, exactly as the Unauthorized branch below
            # already does. This used to hand-write four status-bar fields while leaving
            # $Script:ConnectionStatus untouched, so the button, the dropdowns and the Display name
            # went on claiming the tab was connected. (The writes were in fact unreachable: the guard
            # tested $Script:MainForm.Definitions, which does not exist - the member is Definition -
            # so the status bar was never even updated on this error.)
            Set-SqlConnectionState -Status $false
            $Message | Write-Error -ErrorAction Stop -TargetObject $_
            $Script:RunTimeData.SkipRetryRequest = $true
        }
        elseif ($null -ne $_.Exception?.Response?.StatusCode -and $_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::Unauthorized) {
            $Message = "Access denied to {0}, message:`n`r{1}" -f [system.uri]::New($Script:AppConfig.BaseUrl).Host, $_.ErrorDetails.Message
            Set-SqlConnectionState -Status $false
            $Message | Write-Error -ErrorAction Stop -TargetObject $_
            $Script:RunTimeData.SkipRetryRequest = $true
        }
        else {
            # $Message = "Error occurred:`n`r{1}" -f [system.uri]::New($Script:AppConfig.BaseUrl).Host, $_.ErrorDetails.Message
            # $Message | Write-Error -ErrorAction Stop -TargetObject $_
            $_
        }
    }
    finally {
        Resume-WebViewCompletionPolling
    }
}
