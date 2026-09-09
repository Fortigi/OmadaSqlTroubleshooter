#Requires -Version 7.0
# A background worker must never try to sign in: it has no desktop and its pool is MTA on purpose, so
# an interactive sign-in there fails as a WebView2RuntimeNotFoundException. That is not theoretical -
# in the live session that answered "does background execution survive?", the first query after a
# seventy-minute idle failed exactly that way and switched background execution off.
#
# -NoInteractiveAuthentication (Fortigi/OmadaWeb.PS#85) makes it impossible, and turns an expired
# session from an explosion into a typed, catchable answer.
#
# The capability check is not optional. PowerShell REJECTS an unknown parameter rather than ignoring
# it, and this application's minimum OmadaWeb.PS is 2026.07.09.9 - which predates the switch. Adding
# it unconditionally would break every background request on that version.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Test-OmadaRestMethodParameter.ps1")
    . (Join-Path $PrivatePath -ChildPath "Add-OmadaNonInteractiveAuthentication.ps1")

    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
        process { }
    }

    # The capability probe is its own function precisely so it can be mocked here: mocking
    # Get-Command is unreliable, because Pester uses it itself.
    function script:Set-ModuleSupport {
        param([switch]$SupportsSwitch)

        $Script:TestModuleSupportsSwitch = [bool]$SupportsSwitch
        Mock Test-OmadaRestMethodParameter { return $Script:TestModuleSupportsSwitch }
    }

    function script:New-Splat {
        return @{
            Uri                 = "https://tenant.omada.cloud/odata/x"
            Method              = "GET"
            SessionKey          = "pool-1"
            ForceAuthentication = $true
        }
    }
}

Describe "Add-OmadaNonInteractiveAuthentication" {
    Context "The installed module supports the switch" {
        BeforeEach { Set-ModuleSupport -SupportsSwitch }

        It "adds it, so the worker cannot be pushed into a sign-in" {
            $Private:Result = Add-OmadaNonInteractiveAuthentication -Parameters (New-Splat)

            $Private:Result.NoInteractiveAuthentication | Should -BeTrue
        }

        It "removes ForceAuthentication, which the module refuses alongside it" {
            # One forbids signing in, the other requires it. OmadaWeb.PS rejects the combination up
            # front, so a splat carrying it from an earlier forced login would fail every request.
            $Private:Result = Add-OmadaNonInteractiveAuthentication -Parameters (New-Splat)

            $Private:Result.ContainsKey("ForceAuthentication") | Should -BeFalse
        }

        It "leaves the caller's hashtable untouched" {
            # The caller's copy is the live one the next request is built from.
            $Private:Original = New-Splat

            Add-OmadaNonInteractiveAuthentication -Parameters $Private:Original | Out-Null

            $Private:Original.ContainsKey("NoInteractiveAuthentication") | Should -BeFalse
            $Private:Original.ForceAuthentication | Should -BeTrue
        }

        It "carries the rest of the transport settings through" {
            $Private:Result = Add-OmadaNonInteractiveAuthentication -Parameters (New-Splat)

            $Private:Result.SessionKey | Should -Be "pool-1"
            $Private:Result.Uri | Should -Be "https://tenant.omada.cloud/odata/x"
        }
    }

    Context "The installed module predates the switch" {
        BeforeEach { Set-ModuleSupport }

        It "does not add it, because PowerShell would reject the call outright" {
            # Not a graceful degradation if we get this wrong: an unknown parameter is an error, so
            # every background request would fail rather than merely behave as before.
            $Private:Result = Add-OmadaNonInteractiveAuthentication -Parameters (New-Splat)

            $Private:Result.ContainsKey("NoInteractiveAuthentication") | Should -BeFalse
        }

        It "leaves ForceAuthentication alone, since nothing now conflicts with it" {
            $Private:Result = Add-OmadaNonInteractiveAuthentication -Parameters (New-Splat)

            $Private:Result.ForceAuthentication | Should -BeTrue
        }

        It "drops a stale key if one is somehow already there" {
            $Private:Splat = New-Splat
            $Private:Splat.NoInteractiveAuthentication = $true

            $Private:Result = Add-OmadaNonInteractiveAuthentication -Parameters $Private:Splat

            $Private:Result.ContainsKey("NoInteractiveAuthentication") | Should -BeFalse
        }
    }

    Context "When the capability cannot be determined" {
        It "returns a usable splat rather than stopping the query" {
            Mock Test-OmadaRestMethodParameter { throw "module not loadable" }

            # Assigned outside the scriptblock: a Should -Not -Throw body runs in a child scope, so an
            # assignment made inside it does not survive.
            { Add-OmadaNonInteractiveAuthentication -Parameters (New-Splat) } | Should -Not -Throw

            $Private:Result = Add-OmadaNonInteractiveAuthentication -Parameters (New-Splat)
            $Private:Result.Uri | Should -Be "https://tenant.omada.cloud/odata/x"
        }

        It "does not add the switch it could not verify" {
            Mock Test-OmadaRestMethodParameter { throw "module not loadable" }

            $Private:Result = Add-OmadaNonInteractiveAuthentication -Parameters (New-Splat)

            $Private:Result.ContainsKey("NoInteractiveAuthentication") | Should -BeFalse
        }

        It "strips a key that was already there, rather than passing on one it could not verify" {
            # The version of this test that only checked a splat WITHOUT the key passed against code
            # that left a pre-existing one in place - so it proved nothing about the case that
            # actually breaks a request. An unverifiable capability has to reach the same safe
            # behaviour as a verified absence, by every route including a throw.
            Mock Test-OmadaRestMethodParameter { throw "module not loadable" }
            $Private:Splat = New-Splat
            $Private:Splat.NoInteractiveAuthentication = $true

            $Private:Result = Add-OmadaNonInteractiveAuthentication -Parameters $Private:Splat

            $Private:Result.ContainsKey("NoInteractiveAuthentication") | Should -BeFalse
        }
    }
}

Describe "Test-OmadaRestMethodParameter" {
    It "answers no when OmadaWeb.PS is not loaded" {
        # Not adding an optional parameter is always safe; adding one the module rejects is not, so an
        # unanswerable question is answered no.
        Mock Get-Command { return $null }

        Test-OmadaRestMethodParameter -Name "NoInteractiveAuthentication" | Should -BeFalse
    }

    It "answers from the command's declared parameters, dynamic ones included" {
        # OmadaWeb.PS declares most of its parameters through New-DynamicParam, and those DO appear in
        # Get-Command's .Parameters - verified against 2026.7.9.9 and 2026.9.9 alike.
        Mock Get-Command { return [pscustomobject]@{ Parameters = @{ Uri = $null; NoInteractiveAuthentication = $null } } }

        Test-OmadaRestMethodParameter -Name "NoInteractiveAuthentication" | Should -BeTrue
        Test-OmadaRestMethodParameter -Name "SomethingElse" | Should -BeFalse
    }
}

Describe "The worker's requests carry it" {
    It "is applied in Start-OmadaBackgroundRequest, before either clone" {
        # Applied there rather than in Build-OmadaRequestParameter because it must apply to the worker
        # ONLY - the UI thread is exactly where signing in is supposed to happen. Both worker paths
        # clone from that point, so one call covers the pipeline and the single-request path alike.
        $Private:Source = Get-Content -Path (Join-Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "src\Lib\Functions\Private") "Start-OmadaBackgroundRequest.ps1") -Raw

        $Private:Source | Should -Match '\$Parameters\s*=\s*Add-OmadaNonInteractiveAuthentication\s+-Parameters\s+\$Parameters'
    }

    It "is not applied to requests the UI thread makes" {
        # Build-OmadaRequestParameter prepares BOTH paths. Adding it there would stop the UI thread
        # being able to sign in at all, which is the one place that must be able to.
        $Private:Source = Get-Content -Path (Join-Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "src\Lib\Functions\Private") "Build-OmadaRequestParameter.ps1") -Raw

        $Private:Source | Should -Not -Match 'NoInteractiveAuthentication'
    }
}
