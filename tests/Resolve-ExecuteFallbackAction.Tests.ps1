#Requires -Version 7.0
# The bug this settles, from a live session: a single HTTP 502 from the tenant permanently disabled
# background query execution for the rest of the session. The old rule was "no step completed => the
# worker cannot run requests", which is simply not what a Bad Gateway means. A status code coming back
# is proof the worker reached the tenant.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Get-OmadaHttpStatusCode.ps1")
    . (Join-Path $PrivatePath -ChildPath "Test-OmadaSessionExpiredError.ps1")
    . (Join-Path $PrivatePath -ChildPath "Resolve-ExecuteFallbackAction.ps1")

    function script:New-Outcome {
        param(
            [string]$Message = "boom",
            [int]$CompletedSteps = 0,
            [switch]$NoError
        )
        return @{
            CompletedSteps = $CompletedSteps
            ErrorRecord    = $(if ($NoError) { $null } else {
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new($Message), "TestFailure",
                        [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
                })
        }
    }
}

Describe "Resolve-ExecuteFallbackAction" {
    Context "The tenant answered" {
        It "reports a 502 instead of blaming the worker" {
            # The exact regression. Re-running a 502 on the UI thread sends the identical request and
            # gets the identical answer, and disabling background execution over it costs the user a
            # responsive window all day for one transient blip at the far end.
            New-Outcome -Message "Response status code does not indicate success: 502 (Bad Gateway)." |
                ForEach-Object { Resolve-ExecuteFallbackAction -Outcome $_ } | Should -Be "Report"
        }

        It "reports a 500" {
            New-Outcome -Message "Response status code does not indicate success: 500 (Internal Server Error)." |
                ForEach-Object { Resolve-ExecuteFallbackAction -Outcome $_ } | Should -Be "Report"
        }

        It "reports a 404" {
            New-Outcome -Message "Response status code does not indicate success: 404 (Not Found)." |
                ForEach-Object { Resolve-ExecuteFallbackAction -Outcome $_ } | Should -Be "Report"
        }

        It "retries a 401 without writing off the worker" {
            # The session expired. A worker cannot sign in, but the UI thread can - and once it has,
            # the worker may well work again, so disabling would be the wrong conclusion.
            New-Outcome -Message "Response status code does not indicate success: 401 (Unauthorized)." |
                ForEach-Object { Resolve-ExecuteFallbackAction -Outcome $_ } | Should -Be "Retry"
        }

        It "reports rather than retries once any step has completed" {
            # Re-running could execute the query a second time against the tenant.
            New-Outcome -Message "something failed later" -CompletedSteps 2 |
                ForEach-Object { Resolve-ExecuteFallbackAction -Outcome $_ } | Should -Be "Report"
        }
    }

    Context "The session had gone and the worker refused to sign in" {
        # What a worker now reports instead of exploding: it carries -NoInteractiveAuthentication, so
        # OmadaWeb.PS raises a typed error rather than opening a browser it has no desktop for.

        function script:New-SessionExpiredOutcome {
            param([int]$CompletedSteps = 0)
            $Private:Exception = [System.Security.Authentication.AuthenticationException]::new("The Omada session has expired and -NoInteractiveAuthentication was specified")
            return @{
                CompletedSteps = $CompletedSteps
                ErrorRecord    = [System.Management.Automation.ErrorRecord]::new(
                    $Private:Exception, "OmadaSessionExpired,Invoke-OmadaRequest",
                    [System.Management.Automation.ErrorCategory]::AuthenticationError, "https://tenant.omada.cloud")
            }
        }

        It "retries on the UI thread, which is the one place that can sign in" {
            Resolve-ExecuteFallbackAction -Outcome (New-SessionExpiredOutcome) | Should -Be "Retry"
        }

        It "does NOT write off the worker" {
            # The distinction that matters: an expired session says nothing about whether the worker
            # can run requests. Once the UI thread has signed in there is a session to inherit, and
            # disabling here would give up something that is about to start working - which is exactly
            # what happened in the live session that prompted this.
            Resolve-ExecuteFallbackAction -Outcome (New-SessionExpiredOutcome) | Should -Not -Be "RetryAndDisable"
        }

        It "is preferred over the bare status code, being the more precise answer" {
            # The module raises this for a 401 as well as for no cookie at all, so "401 with no
            # sign-in attempted" beats "401".
            $Private:Outcome = New-SessionExpiredOutcome
            $Private:Outcome.ErrorRecord.Exception | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = 401 }) -Force

            Resolve-ExecuteFallbackAction -Outcome $Private:Outcome | Should -Be "Retry"
        }

        It "still reports rather than retries once a step has completed" {
            # Re-running could execute the query a second time against the tenant, expiry or not.
            Resolve-ExecuteFallbackAction -Outcome (New-SessionExpiredOutcome -CompletedSteps 2) | Should -Be "Report"
        }
    }

    Context "The worker could not run the request" {
        It "disables when nothing came back at all" {
            Resolve-ExecuteFallbackAction -Outcome $null | Should -Be "RetryAndDisable"
        }

        It "disables when the outcome carries no error and no evidence of work" {
            Resolve-ExecuteFallbackAction -Outcome (New-Outcome -NoError) | Should -Be "RetryAndDisable"
        }

        It "disables when the worker was pushed into a sign-in it cannot perform" {
            # The failure observed on a real machine: an MTA worker has no desktop to host WebView2.
            $Private:Message = "Start-WebView2Login - Error creating CoreWebView2Environment ... Microsoft.Web.WebView2.Core.WebView2RuntimeNotFoundException: Couldn't find a compatible Webview2 Runtime installation to host WebViews."
            Resolve-ExecuteFallbackAction -Outcome (New-Outcome -Message $Private:Message) | Should -Be "RetryAndDisable"
        }
    }

    Context "Anything else" {
        It "retries but does not disable, because disabling is a one-way door" {
            # Conservative on purpose: an unrecognised failure is not evidence that the worker is
            # incapable, and the cost of being wrong is asymmetric.
            Resolve-ExecuteFallbackAction -Outcome (New-Outcome -Message "something nobody has seen before") | Should -Be "Retry"
        }
    }
}

Describe "Get-OmadaHttpStatusCode" {
    It "reads the code from the message a worker's error arrives as" {
        $Private:Record = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Response status code does not indicate success: 502 (Bad Gateway)."), "x",
            [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

        Get-OmadaHttpStatusCode -ErrorRecord $Private:Record | Should -Be 502
    }

    It "prefers the exception's own status when it survived" {
        $Private:Exception = [System.Exception]::new("no code in this text")
        $Private:Exception | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = 503 }) -Force
        $Private:Record = [System.Management.Automation.ErrorRecord]::new($Private:Exception, "x", [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

        Get-OmadaHttpStatusCode -ErrorRecord $Private:Record | Should -Be 503
    }

    It "does not depend on the casing of someone else's message" {
        # The wording comes from HttpClient and is wrapped by however many layers before it reaches
        # here. Pinning the casing would bet the whole classification - and with it whether one tenant
        # hiccup disables background execution - on a formatting detail.
        $Private:Record = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Response Status Code Does Not Indicate Success: 502 (Bad Gateway)."), "x",
            [System.Management.Automation.ErrorCategory]::ConnectionError, $null)

        Get-OmadaHttpStatusCode -ErrorRecord $Private:Record | Should -Be 502
    }

    It "returns null when the failure is not an HTTP response" {
        $Private:Record = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Couldn't find a compatible Webview2 Runtime"), "x",
            [System.Management.Automation.ErrorCategory]::NotInstalled, $null)

        Get-OmadaHttpStatusCode -ErrorRecord $Private:Record | Should -BeNullOrEmpty
    }

    It "returns null for a null error" {
        Get-OmadaHttpStatusCode -ErrorRecord $null | Should -BeNullOrEmpty
    }
}
