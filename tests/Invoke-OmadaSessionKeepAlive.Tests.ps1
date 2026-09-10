#Requires -Version 7.0
# Issue #89. An Omada session expires in roughly ten minutes; an application that is open but idle
# loses it with nothing on screen changing. Measured, not assumed: in the live session that answered
# "does background execution survive?", five queries ran in nine minutes, the application sat idle
# for seventy, and the first query after the idle failed because the session had gone.
#
# The hard requirement, and the reason this could not be built until Fortigi/OmadaWeb.PS#85 shipped
# -NoInteractiveAuthentication: it must NEVER put a sign-in in front of the user. A keep-alive that
# can open a login window at an arbitrary moment is worse than no keep-alive.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Test-OmadaSessionExpiredError.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SessionKeepAliveInterval.ps1")
    . (Join-Path $PrivatePath -ChildPath "Invoke-OmadaSessionKeepAlive.ps1")

    $script:LogMessages = [System.Collections.Generic.List[object]]::new()
    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
        process { $script:LogMessages.Add([pscustomobject]@{ LogType = $LogType; Message = [string]$InputObject }) }
    }

    function Get-ConfigSchemaDefault { param([string]$Property, [string]$SchemaPath) return 5 }

    # The transport. Records every request so the tests can assert what was sent, and answers with
    # whatever the test set up.
    $script:Requests = [System.Collections.Generic.List[object]]::new()
    function Invoke-OmadaRequestCore {
        param([hashtable]$Parameters)
        $script:Requests.Add($Parameters)
        if ($null -ne $script:NextError) { return @{ Result = $null; ErrorRecord = $script:NextError } }
        return @{ Result = [pscustomobject]@{ value = @() }; ErrorRecord = $null }
    }

    function script:New-SessionExpiredError {
        $Exception = [System.Security.Authentication.AuthenticationException]::new("The Omada session has expired")
        return [System.Management.Automation.ErrorRecord]::new($Exception, "OmadaSessionExpired,Invoke-OmadaRequest", [System.Management.Automation.ErrorCategory]::AuthenticationError, "https://tenant.omada.cloud")
    }

    function script:New-TransientError {
        return [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Response status code does not indicate success: 502 (Bad Gateway)."),
            "Transient", [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
    }

    function script:New-Tab {
        param([string]$Id, [string]$SessionKey, [bool]$Connected = $true, [string]$BaseUrl = "https://tenant.omada.cloud")
        return [pscustomobject]@{
            Id               = $Id
            ConnectionStatus = $Connected
            AppConfig        = [pscustomobject]@{ BaseUrl = $BaseUrl }
            RunTimeData      = [pscustomobject]@{
                RestMethodParam = @{
                    Uri                 = "https://tenant.omada.cloud/something/else"
                    Method              = "POST"
                    Body                = @{ leftover = $true }
                    SessionKey          = $SessionKey
                    AuthenticationType  = "WebView2"
                    ForceAuthentication = $true
                }
            }
        }
    }

    function script:Initialize-KeepAliveState {
        $script:LogMessages.Clear()
        $script:Requests.Clear()
        $script:NextError = $null
        $Script:LastSessionKeepAliveUtc = $null
        $Script:SessionKeepAliveAbandoned = @{}
        $Script:AppGlobalConfig = [pscustomobject]@{ SessionKeepAliveMinutes = 5 }
        $Script:Tabs = @(New-Tab -Id "A" -SessionKey "pool-1")
    }
}

Describe "Invoke-OmadaSessionKeepAlive" {
    BeforeEach { Initialize-KeepAliveState }

    It "refreshes a connected session" {
        Invoke-OmadaSessionKeepAlive

        @($script:Requests).Count | Should -Be 1
    }

    It "never allows a sign-in prompt" {
        # The requirement the whole feature turns on. Without this switch an expired session mid-ping
        # puts a login window over whatever the user is doing, at a moment they did not choose.
        Invoke-OmadaSessionKeepAlive

        $script:Requests[0].NoInteractiveAuthentication | Should -BeTrue
    }

    It "drops ForceAuthentication, which OmadaWeb.PS refuses alongside it" {
        # One forbids signing in, the other requires it; the module rejects the combination outright,
        # so a tab carrying it from an earlier forced login would fail every ping.
        Invoke-OmadaSessionKeepAlive

        $script:Requests[0].ContainsKey("ForceAuthentication") | Should -BeFalse
    }

    It "asks for one row rather than the whole query list" {
        Invoke-OmadaSessionKeepAlive

        $script:Requests[0].Uri | Should -Match '\$top=1'
        $script:Requests[0].Method | Should -Be "GET"
        $script:Requests[0].ContainsKey("Body") | Should -BeFalse
    }

    It "does not disturb the tab's own request parameters" {
        # It clones. The live hashtable is what that tab's next real request is built from.
        Invoke-OmadaSessionKeepAlive

        $Script:Tabs[0].RunTimeData.RestMethodParam.Method | Should -Be "POST"
        $Script:Tabs[0].RunTimeData.RestMethodParam.Uri | Should -Be "https://tenant.omada.cloud/something/else"
    }

    It "says nothing above DEBUG - a keep-alive the user notices has failed" {
        Invoke-OmadaSessionKeepAlive

        @($script:LogMessages | Where-Object { $_.LogType -ne "DEBUG" }).Count | Should -Be 0
    }

    Context "Which sessions get pinged" {
        It "skips a tab that is not connected" {
            $Script:Tabs = @(New-Tab -Id "A" -SessionKey "pool-1" -Connected $false)

            Invoke-OmadaSessionKeepAlive

            @($script:Requests).Count | Should -Be 0
        }

        It "pings once per session, not once per tab" {
            # Tabs sharing a SessionKey share one OmadaWeb.PS session, so one ping serves them all.
            $Script:Tabs = @(
                (New-Tab -Id "A" -SessionKey "pool-1"),
                (New-Tab -Id "B" -SessionKey "pool-1"),
                (New-Tab -Id "C" -SessionKey "pool-1")
            )

            Invoke-OmadaSessionKeepAlive

            @($script:Requests).Count | Should -Be 1
        }

        It "pings each distinct session" {
            $Script:Tabs = @(
                (New-Tab -Id "A" -SessionKey "pool-1"),
                (New-Tab -Id "B" -SessionKey "pool-2" -BaseUrl "https://other.omada.cloud")
            )

            Invoke-OmadaSessionKeepAlive

            @($script:Requests).Count | Should -Be 2
        }
    }

    Context "Timing" {
        It "does not ping again before the interval has passed" {
            Invoke-OmadaSessionKeepAlive
            Invoke-OmadaSessionKeepAlive
            Invoke-OmadaSessionKeepAlive

            @($script:Requests).Count | Should -Be 1
        }

        It "pings again once it has" {
            Invoke-OmadaSessionKeepAlive
            $Script:LastSessionKeepAliveUtc = [DateTime]::UtcNow.AddMinutes(-6)

            Invoke-OmadaSessionKeepAlive

            @($script:Requests).Count | Should -Be 2
        }

        It "stamps the time before the request, so a slow tenant cannot stack rounds" {
            Mock Invoke-OmadaRequestCore {
                $script:Requests.Add($Parameters)
                # A tick landing while the first round is still in flight.
                Invoke-OmadaSessionKeepAlive
                return @{ Result = $null; ErrorRecord = $null }
            }

            Invoke-OmadaSessionKeepAlive

            @($script:Requests).Count | Should -Be 1
        }

        It "is switched off entirely by an interval of zero" {
            $Script:AppGlobalConfig = [pscustomobject]@{ SessionKeepAliveMinutes = 0 }

            Invoke-OmadaSessionKeepAlive

            @($script:Requests).Count | Should -Be 0
        }
    }

    Context "When the session has gone" {
        BeforeEach { $script:NextError = New-SessionExpiredError }

        It "stops pinging that session rather than asking again every interval" {
            Invoke-OmadaSessionKeepAlive
            $Script:LastSessionKeepAliveUtc = [DateTime]::UtcNow.AddMinutes(-6)
            Invoke-OmadaSessionKeepAlive

            @($script:Requests).Count | Should -Be 1
        }

        It "still says nothing above DEBUG" {
            # The user finds out when they next do something. A dialog from a timer about a session
            # they were not using is exactly the interruption this feature exists to avoid.
            Invoke-OmadaSessionKeepAlive

            @($script:LogMessages | Where-Object { $_.LogType -ne "DEBUG" }).Count | Should -Be 0
        }

        It "abandons only the session that failed" {
            $Script:Tabs = @(
                (New-Tab -Id "A" -SessionKey "pool-1"),
                (New-Tab -Id "B" -SessionKey "pool-2" -BaseUrl "https://other.omada.cloud")
            )
            Mock Invoke-OmadaRequestCore {
                $script:Requests.Add($Parameters)
                if ($Parameters.SessionKey -eq "pool-1") { return @{ Result = $null; ErrorRecord = (New-SessionExpiredError) } }
                return @{ Result = [pscustomobject]@{}; ErrorRecord = $null }
            }

            Invoke-OmadaSessionKeepAlive
            $Script:LastSessionKeepAliveUtc = [DateTime]::UtcNow.AddMinutes(-6)
            $script:Requests.Clear()
            Invoke-OmadaSessionKeepAlive

            @($script:Requests).Count | Should -Be 1
            $script:Requests[0].SessionKey | Should -Be "pool-2"
        }
    }

    Context "Giving up is not permanent" {
        BeforeEach { $script:NextError = New-SessionExpiredError }

        It "resumes for a session that has been signed into again" {
            # SessionKey is a stable hash of the connection identity, so it is the SAME key after
            # signing in again. Without a reset, one expiry would switch the keep-alive off for that
            # tenant and identity for the rest of the application's life - which is precisely the
            # silent expiry this feature exists to prevent.
            Invoke-OmadaSessionKeepAlive
            $script:NextError = $null

            Reset-SessionKeepAlive
            $Script:LastSessionKeepAliveUtc = [DateTime]::UtcNow.AddMinutes(-6)
            $script:Requests.Clear()

            Invoke-OmadaSessionKeepAlive

            @($script:Requests).Count | Should -Be 1
        }

        It "does not ping immediately on reconnect, so a just-connected tab is left alone" {
            Reset-SessionKeepAlive

            Invoke-OmadaSessionKeepAlive

            @($script:Requests).Count | Should -Be 0
        }
    }

    Context "When the tenant merely had a bad moment" {
        It "tries again next interval, because a 502 says nothing about the session" {
            $script:NextError = New-TransientError

            Invoke-OmadaSessionKeepAlive
            $Script:LastSessionKeepAliveUtc = [DateTime]::UtcNow.AddMinutes(-6)
            Invoke-OmadaSessionKeepAlive

            @($script:Requests).Count | Should -Be 2
        }
    }
}

Describe "Test-OmadaSessionExpiredError" {
    It "recognises the error id, which is a prefix because PowerShell appends to it" {
        Test-OmadaSessionExpiredError -ErrorRecord (New-SessionExpiredError) | Should -BeTrue
    }

    It "recognises the exception type on its own" {
        $Private:Record = [System.Management.Automation.ErrorRecord]::new(
            [System.Security.Authentication.AuthenticationException]::new("gone"),
            "SomethingElse", [System.Management.Automation.ErrorCategory]::AuthenticationError, $null)

        Test-OmadaSessionExpiredError -ErrorRecord $Private:Record | Should -BeTrue
    }

    It "finds it wrapped as an inner exception" {
        $Private:Inner = [System.Security.Authentication.AuthenticationException]::new("gone")
        $Private:Record = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("outer", $Private:Inner),
            "Wrapped", [System.Management.Automation.ErrorCategory]::NotSpecified, $null)

        Test-OmadaSessionExpiredError -ErrorRecord $Private:Record | Should -BeTrue
    }

    It "recognises an exception that crossed a runspace boundary" {
        # GetType() on a deserialized exception returns System.Management.Automation.PSObject, not
        # the original type - so a check written against GetType() silently never matches, and every
        # expiry coming back from a worker would be classified as a transient failure and retried
        # forever. The real type survives in PSObject.TypeNames, prefixed "Deserialized.".
        $Private:Live = [System.Security.Authentication.AuthenticationException]::new("gone")
        $Private:Deserialized = [System.Management.Automation.PSSerializer]::Deserialize(
            [System.Management.Automation.PSSerializer]::Serialize($Private:Live))

        # The premise, asserted so this test cannot quietly stop testing anything.
        $Private:Deserialized.GetType().FullName | Should -Be "System.Management.Automation.PSObject"

        $Private:Record = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("outer"), "SomethingElse",
            [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
        $Private:Record.Exception | Add-Member -NotePropertyName InnerException -NotePropertyValue $Private:Deserialized -Force

        Test-OmadaSessionExpiredError -ErrorRecord $Private:Record | Should -BeTrue
    }

    It "does not mistake a transient failure for an expiry" {
        Test-OmadaSessionExpiredError -ErrorRecord (New-TransientError) | Should -BeFalse
    }

    It "does not hang on a self-referencing exception chain" {
        # It runs from the poll timer; a cycle here would freeze the window.
        $Private:Exception = [System.Exception]::new("loop")
        $Private:Exception | Add-Member -NotePropertyName InnerException -NotePropertyValue $Private:Exception -Force
        $Private:Record = [System.Management.Automation.ErrorRecord]::new($Private:Exception, "x", [System.Management.Automation.ErrorCategory]::NotSpecified, $null)

        Test-OmadaSessionExpiredError -ErrorRecord $Private:Record | Should -BeFalse
    }

    It "is not confused by a null" {
        Test-OmadaSessionExpiredError -ErrorRecord $null | Should -BeFalse
    }
}

Describe "Get-SessionKeepAliveInterval" {
    BeforeEach { Initialize-KeepAliveState }

    It "uses the stored value" {
        $Script:AppGlobalConfig = [pscustomobject]@{ SessionKeepAliveMinutes = 3 }
        Get-SessionKeepAliveInterval | Should -Be 3
    }

    It "treats zero as off rather than as absent" {
        $Script:AppGlobalConfig = [pscustomobject]@{ SessionKeepAliveMinutes = 0 }
        Get-SessionKeepAliveInterval | Should -Be 0
    }

    It "falls back to the default for the -1 an Int property carries when unset" {
        # Never to zero: that would silently disable a feature nobody asked to disable.
        $Script:AppGlobalConfig = [pscustomobject]@{ SessionKeepAliveMinutes = -1 }
        Get-SessionKeepAliveInterval | Should -Be 5
    }

    It "falls back to the default for a non-numeric value" {
        $Script:AppGlobalConfig = [pscustomobject]@{ SessionKeepAliveMinutes = "soon" }
        Get-SessionKeepAliveInterval | Should -Be 5
    }

    It "falls back to the default when nothing is stored" {
        $Script:AppGlobalConfig = [pscustomobject]@{}
        Get-SessionKeepAliveInterval | Should -Be 5
    }
}
