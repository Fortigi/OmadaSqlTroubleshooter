BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Protect-LogMessage.ps1"
    . $Command
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }
}

Describe 'Protect-LogMessage' {

    Context 'Authorization material' {

        It 'masks a Basic authorization header' {
            $Result = Protect-LogMessage -Message "Authorization: Basic b21hZGE6UzNjcjN0UGFzcw=="

            $Result | Should -Not -Match "b21hZGE6UzNjcjN0UGFzcw"
            $Result | Should -Match "REDACTED"
        }

        It 'masks a Bearer token' {
            $Result = Protect-LogMessage -Message "Authorization: Bearer abcdef1234567890abcdef"

            $Result | Should -Not -Match "abcdef1234567890"
        }

        It 'masks a bare JWT that appears without a scheme prefix' {
            $Jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NSJ9.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk"
            $Result = Protect-LogMessage -Message "Cached response token $Jwt for tenant"

            $Result | Should -Not -Match "dBjftJeZ4CVPmB92K27uhbUJU1p1r"
            $Result | Should -Match "tenant"
        }

        It 'leaves the scheme name alone when it is not followed by a token' {
            # "Basic" as an authentication-type value is useful diagnostic information.
            Protect-LogMessage -Message "AuthenticationType: Basic" | Should -Match "Basic"
        }
    }

    Context 'Serialized key/value pairs' {

        It 'masks a JSON <_> pair' -ForEach @("Password", "Authorization", "Token", "Secret", "ApiKey", "Cookie") {
            $Result = Protect-LogMessage -Message ('{{"{0}": "LeakedValue987"}}' -f $_)

            $Result | Should -Not -Match "LeakedValue987"
            $Result | Should -Match "REDACTED"
        }

        It 'still masks a Credential pair holding anything other than the safe rendering' {
            Protect-LogMessage -Message '{"Credential": "omada\\svc_sql:Sup3rSecret!"}' | Should -Not -Match "Sup3rSecret"
        }

        It 'keeps the credential rendering ConvertTo-RedactedLogString deliberately emits' {
            # Otherwise the safety net would undo the walker's decision to report which account
            # authenticated. The rendering carries a user name and no password.
            $Result = Protect-LogMessage -Message '{"Credential": "PSCredential(UserName=omada\\svc_sql)"}'

            $Result | Should -Match "svc_sql"
        }

        It 'masks a query-string style password' {
            Protect-LogMessage -Message "url=https://tenant/api?user=bob&password=P@ssw0rd123" | Should -Not -Match "P@ssw0rd123"
        }

        It 'masks a session cookie value' {
            $Result = Protect-LogMessage -Message "Set-Cookie: ASP.NET_SessionId=n3v3rl0gth1svalue; path=/"

            $Result | Should -Not -Match "n3v3rl0gth1svalue"
        }
    }

    Context 'Non-sensitive text' {

        It 'leaves an ordinary log line untouched' {
            $Message = "2026-08-13 10:00:00 - INFO    - Main - Invoke-ExecuteQuery (56): Retrieve query output, please wait..."

            Protect-LogMessage -Message $Message | Should -BeExactly $Message
        }

        It 'keeps the request URL, which is diagnostic' {
            Protect-LogMessage -Message "QueryUrl: https://tenant.omada.cloud/OData/BuiltIn/C_P_SQLTROUBLESHOOTING" |
                Should -Match "C_P_SQLTROUBLESHOOTING"
        }
    }

    Context 'Robustness' {

        It 'handles $null without throwing' {
            { Protect-LogMessage -Message $null } | Should -Not -Throw
        }

        It 'handles an empty string without throwing' {
            { Protect-LogMessage -Message "" } | Should -Not -Throw
        }

        It 'accepts pipeline input' {
            "Authorization: Bearer abcdef1234567890abcdef" | Protect-LogMessage | Should -Not -Match "abcdef1234567890"
        }
    }
}
