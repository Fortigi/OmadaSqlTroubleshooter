#Requires -Version 7.0
# The request-preparation rules, extracted from Invoke-OmadaPSWebRequestWrapper by issue #40 so the
# synchronous and background paths prepare a request identically. These assert the rules directly,
# where Invoke-OmadaPSWebRequestWrapper.Tests.ps1 continues to assert them through the wrapper - so
# a change that breaks preparation fails in a test that names it, not only in a transport test.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Build-OmadaRequestParameter.ps1")

    function script:Initialize-PreparationState {
        param(
            [string]$AuthenticationType = "Browser",
            [bool]$UseWebView2Auth = $false,
            $Body = $null
        )
        $Script:RunTimeConfig = [PSCustomObject]@{ UseWebView2Auth = $UseWebView2Auth }
        $Script:SkipBodyRedaction = $false
        $Script:RunTimeData = [PSCustomObject]@{
            RestMethodParam = @{
                Uri                = "https://tenant.omada.cloud/probe"
                Method             = "GET"
                AuthenticationType = $AuthenticationType
                Body               = $Body
            }
        }
    }

    function Invoke-OmadaRestMethod {
        [CmdletBinding()]
        param([Parameter(ValueFromRemainingArguments = $true)]$IgnoredRest)
    }
}

Describe "Build-OmadaRequestParameter" {
    It "enables WebView2 only for Browser authentication when the session asked for it" {
        Initialize-PreparationState -AuthenticationType "Browser" -UseWebView2Auth $true

        (Build-OmadaRequestParameter).UseWebView2 | Should -BeTrue
    }

    It "leaves WebView2 off for Browser authentication when the session did not ask for it" {
        Initialize-PreparationState -AuthenticationType "Browser" -UseWebView2Auth $false

        (Build-OmadaRequestParameter).UseWebView2 | Should -BeFalse
    }

    It "never enables WebView2 for a non-Browser authentication option" {
        Initialize-PreparationState -AuthenticationType "Windows" -UseWebView2Auth $true

        (Build-OmadaRequestParameter).UseWebView2 | Should -BeFalse
    }

    It "removes a null Body rather than sending one" {
        Initialize-PreparationState -Body $null

        (Build-OmadaRequestParameter).ContainsKey("Body") | Should -BeFalse
    }

    It "keeps a populated Body" {
        Initialize-PreparationState -Body @{ dataType = "SqlDataProducer" }

        (Build-OmadaRequestParameter).Body.dataType | Should -Be "SqlDataProducer"
    }

    It "returns the live RestMethodParam instance, which is why dispatchers must clone it" {
        # Documented behaviour, not an accident: the wrapper has always mutated and reused this one
        # hashtable. It is exactly why Start-OmadaBackgroundRequest clones before crossing into a
        # worker - the next call site overwrites Uri, Method and Body under a request in flight.
        Initialize-PreparationState

        [object]::ReferenceEquals((Build-OmadaRequestParameter), $Script:RunTimeData.RestMethodParam) | Should -BeTrue
    }

    Context "ForceAuthentication is passed only when it is true" {
        # OmadaWeb.PS decides whether to load its encrypted cookie cache with
        # "$BoundParams.Keys -notcontains 'ForceAuthentication'" - it tests whether the parameter was
        # BOUND, not its value. Splatting $false on every request therefore meant the cache was never
        # read by anyone, ever. Invisible on the UI thread, where the in-memory session already holds
        # the cookie - and fatal in a worker runspace, which has no session and so was forced into an
        # interactive WebView2 login that cannot work there.

        It "removes the key when it is false" {
            Initialize-PreparationState
            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false

            (Build-OmadaRequestParameter).ContainsKey("ForceAuthentication") | Should -BeFalse
        }

        It "removes the key when it is absent or null" {
            Initialize-PreparationState
            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $null

            (Build-OmadaRequestParameter).ContainsKey("ForceAuthentication") | Should -BeFalse
        }

        It "keeps the key when it is true, so a forced login still forces one" {
            # Test-OmadaConnection sets this on retry precisely to bypass the cache. That has to keep
            # working, or a stale cookie could never be replaced.
            Initialize-PreparationState
            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $true

            $Prepared = Build-OmadaRequestParameter
            $Prepared.ContainsKey("ForceAuthentication") | Should -BeTrue
            $Prepared.ForceAuthentication | Should -BeTrue
        }

        It "is idempotent across the app's set-false-after-success cycle" {
            # The wrapper writes ForceAuthentication = $false back onto the live hashtable after every
            # successful request, so preparation must be able to strip it again next time.
            Initialize-PreparationState
            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $true
            (Build-OmadaRequestParameter).ContainsKey("ForceAuthentication") | Should -BeTrue

            $Script:RunTimeData.RestMethodParam.ForceAuthentication = $false
            (Build-OmadaRequestParameter).ContainsKey("ForceAuthentication") | Should -BeFalse
        }
    }

    Context "SkipBodyRedaction capability check" {
        It "does not add the key when the installed OmadaWeb.PS does not declare it" {
            # Splatting a parameter a cmdlet does not have is a terminating error, so the key must
            # stay out rather than be passed and fail.
            Initialize-PreparationState
            $Script:SkipBodyRedaction = $true

            function Invoke-OmadaRestMethod {
                [CmdletBinding()]
                param([Parameter(ValueFromRemainingArguments = $true)]$IgnoredRest)
            }

            (Build-OmadaRequestParameter).ContainsKey("SkipBodyRedaction") | Should -BeFalse
        }

        It "passes the current state when the installed OmadaWeb.PS declares it" {
            Initialize-PreparationState
            $Script:SkipBodyRedaction = $true

            function Invoke-OmadaRestMethod {
                [CmdletBinding()]
                param([switch]$SkipBodyRedaction, [Parameter(ValueFromRemainingArguments = $true)]$IgnoredRest)
            }

            (Build-OmadaRequestParameter).SkipBodyRedaction | Should -BeTrue
        }

        It "drops a stale key when the module was downgraded mid-session" {
            Initialize-PreparationState
            $Script:RunTimeData.RestMethodParam.SkipBodyRedaction = $true

            function Invoke-OmadaRestMethod {
                [CmdletBinding()]
                param([Parameter(ValueFromRemainingArguments = $true)]$IgnoredRest)
            }

            (Build-OmadaRequestParameter).ContainsKey("SkipBodyRedaction") | Should -BeFalse
        }
    }
}
