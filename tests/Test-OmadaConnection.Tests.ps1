#Requires -Version 7.0
# Test-OmadaConnection: an InPrivate session signs in once per application run.
#
# Since issue #40 the app leaves ForceAuthentication unbound so background workers can load
# OmadaWeb.PS's on-disk cookie, and OmadaWeb.PS loads that cookie whatever -InPrivate says. An
# InPrivate tab therefore reconnected after a restart without a login. What is asserted here is when
# the connect FORCES a sign-in: the first time per session in a run, and not again after it worked.
#
# The request is stubbed and records ForceAuthentication at the moment it is made, which is the only
# value OmadaWeb.PS ever sees.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Test-OmadaConnection.ps1")

    $script:LogMessages = [System.Collections.Generic.List[object]]::new()
    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog)
        process { $script:LogMessages.Add([pscustomobject]@{ LogType = $LogType; Message = [string]$InputObject }) }
    }

    function Get-ActiveTabSession { return [pscustomobject]@{ Id = "tab-1" } }
    function Get-TabConnectionIdentity { param($TabSession) return $script:Identity }
    function Set-SqlConnectionState { param([bool]$Status) $script:ConnectionStateCalls++ }

    function Invoke-OmadaPSWebRequestWrapper {
        $script:ForcedAtRequest.Add([bool]$Script:RunTimeData.RestMethodParam.ForceAuthentication)
        if ($script:RequestFails) {
            throw [System.Exception]::new("sign-in cancelled")
        }

        return "ok"
    }

    function script:Set-TestIdentity {
        param([string]$Key)
        $script:Identity = [pscustomobject]@{ Key = $Key; IsEmpty = $false }
    }

    function script:Reset-ConnectionState {
        param([bool]$InPrivate = $true)

        $Script:InPrivateSignedInSessionKeys = [System.Collections.Generic.HashSet[string]]::new()
        $Script:AppConfig = [pscustomobject]@{ BaseUrl = "https://tenant.example" }
        $Script:RunTimeData = [pscustomobject]@{
            RestMethodParam          = @{ SessionKey = "tab-1"; InPrivate = $InPrivate }
            AuthenticationRetryCount = 0
        }

        Set-TestIdentity -Key "session-a"
        $script:ForcedAtRequest = [System.Collections.Generic.List[bool]]::new()
        $script:RequestFails = $false
        $script:ConnectionStateCalls = 0
        $script:LogMessages.Clear()
    }
}

Describe "Test-OmadaConnection - InPrivate signs in once per application run" {

    BeforeEach {
        Reset-ConnectionState
    }

    It "forces a sign-in on the first connect of the run" {
        Test-OmadaConnection | Should -BeTrue

        $script:ForcedAtRequest | Should -Be @($true)
    }

    It "does not force it again for the same session" {
        # A second tab on the same session, or a reconnect, reuses the fresh cookie.
        Test-OmadaConnection | Out-Null
        Test-OmadaConnection | Out-Null

        $script:ForcedAtRequest | Should -Be @($true, $false)
    }

    It "forces it for a different session" {
        Test-OmadaConnection | Out-Null
        Set-TestIdentity -Key "session-b"

        Test-OmadaConnection | Out-Null

        $script:ForcedAtRequest | Should -Be @($true, $true)
    }

    It "clears the force after a successful sign-in" {
        # Left set, it would also keep every later request of this tab on the UI thread.
        Test-OmadaConnection | Out-Null

        $Script:RunTimeData.RestMethodParam.ForceAuthentication | Should -BeFalse
    }

    It "forces it again after a failed sign-in" {
        $script:RequestFails = $true
        Test-OmadaConnection | Should -BeFalse

        $script:RequestFails = $false
        Test-OmadaConnection | Should -BeTrue

        $script:ForcedAtRequest | Should -Be @($true, $true) -Because "a failed sign-in must not count as signed in"
    }

    It "forces it again in a new application run" {
        # Invoke-OmadaSqlTroubleshooter resets the set on every start; module state survives between
        # runs in one PowerShell window.
        Test-OmadaConnection | Out-Null
        $Script:InPrivateSignedInSessionKeys = [System.Collections.Generic.HashSet[string]]::new()

        Test-OmadaConnection | Out-Null

        $script:ForcedAtRequest | Should -Be @($true, $true)
    }

    It "works when the set has not been created yet" {
        $Script:InPrivateSignedInSessionKeys = $null

        Test-OmadaConnection | Should -BeTrue

        $script:ForcedAtRequest | Should -Be @($true)
    }
}

Describe "Test-OmadaConnection - a regular session is not forced" {

    BeforeEach {
        Reset-ConnectionState -InPrivate $false
    }

    It "never forces a sign-in" {
        Test-OmadaConnection | Out-Null
        Test-OmadaConnection | Out-Null

        $script:ForcedAtRequest | Should -Be @($false, $false)
    }
}
