BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\ConvertTo-RedactedLogString.ps1"
    . $Command
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    # A real PSCredential - the password must never survive serialization.
    $Script:TestPassword = "Sup3rSecret!"
    $Script:TestCredential = [PSCredential]::new("omada\serviceaccount", (ConvertTo-SecureString $Script:TestPassword -AsPlainText -Force))
}

Describe 'ConvertTo-RedactedLogString' {

    Context 'Sensitive keys' {

        It 'masks the <_> key at the top level' -ForEach @(
            "Authorization", "Cookie", "Credential", "Password", "Secret", "Token", "ApiKey", "ClientSecret", "SessionKey"
        ) {
            $Result = ConvertTo-RedactedLogString -InputObject @{ $_ = "TopSecretValue123" }

            $Result | Should -Not -Match "TopSecretValue123"
            $Result | Should -Match "REDACTED"
        }

        It 'matches key names case-insensitively' {
            $Result = ConvertTo-RedactedLogString -InputObject @{ "AUTHORIZATION" = "Basic dXNlcjpwYXNz" }

            $Result | Should -Not -Match "dXNlcjpwYXNz"
        }

        It 'matches sensitive names as a substring so composite headers are covered' {
            # Real header/property names seen in the wild: X-CSRF-Token, RefreshToken, SessionCookie.
            $Result = ConvertTo-RedactedLogString -InputObject @{
                "X-CSRF-Token"  = "csrf-abcdef"
                "RefreshToken"  = "refresh-abcdef"
                "SessionCookie" = "cookie-abcdef"
            }

            $Result | Should -Not -Match "abcdef"
        }

        It 'masks sensitive keys nested several levels deep' {
            $Result = ConvertTo-RedactedLogString -InputObject @{
                Level1 = @{
                    Level2 = @{
                        Headers = @{ Authorization = "Bearer nested-secret-value" }
                    }
                }
            }

            $Result | Should -Not -Match "nested-secret-value"
            $Result | Should -Match "REDACTED"
        }

        It 'masks sensitive keys inside array elements' {
            $Result = ConvertTo-RedactedLogString -InputObject @(
                @{ Name = "first"; Password = "array-secret-value" }
            )

            $Result | Should -Not -Match "array-secret-value"
        }

        It 'masks sensitive properties on a PSCustomObject as well as a hashtable' {
            $Result = ConvertTo-RedactedLogString -InputObject ([PSCustomObject]@{ Uri = "https://tenant.omada.cloud"; Token = "pscustom-secret" })

            $Result | Should -Not -Match "pscustom-secret"
            $Result | Should -Match "tenant.omada.cloud"
        }
    }

    Context 'Sensitive types' {

        It 'never serializes the password of a PSCredential' {
            $Result = ConvertTo-RedactedLogString -InputObject @{ Credential = $Script:TestCredential }

            $Result | Should -Not -Match ([regex]::Escape($Script:TestPassword))
        }

        It 'keeps the PSCredential user name, which is diagnostic and not secret' {
            # The credential arrives under a non-sensitive key name here, so only the type rule can save us.
            $Result = ConvertTo-RedactedLogString -InputObject @{ Identity = $Script:TestCredential }

            $Result | Should -Match "serviceaccount"
            $Result | Should -Not -Match ([regex]::Escape($Script:TestPassword))
        }

        It 'keeps the user name even under the sensitive key name Credential' {
            # The type rule wins over the name rule here: which account authenticated is exactly what
            # you need to know when troubleshooting a 401, and the password never leaves the SecureString.
            $Result = ConvertTo-RedactedLogString -InputObject @{ Credential = $Script:TestCredential }

            $Result | Should -Match "serviceaccount"
            $Result | Should -Not -Match ([regex]::Escape($Script:TestPassword))
        }

        It 'masks a bare SecureString' {
            $Secure = ConvertTo-SecureString "secure-string-secret" -AsPlainText -Force
            $Result = ConvertTo-RedactedLogString -InputObject @{ Value = $Secure }

            $Result | Should -Not -Match "secure-string-secret"
            $Result | Should -Match "REDACTED"
        }

        It 'reduces a byte array to its length instead of dumping its contents' {
            $Result = ConvertTo-RedactedLogString -InputObject @{ Payload = [byte[]]@(1, 2, 3, 4, 5) }

            $Result | Should -Match "Byte\[5\]"
        }
    }

    Context 'Request bodies' {

        It 'keeps body keys and value shapes but not the values' {
            $Result = ConvertTo-RedactedLogString -InputObject @{
                Uri  = "https://tenant.omada.cloud/odata"
                Body = @{ query = "SELECT * FROM dbo.Identity"; page = 1 }
            }

            $Result | Should -Match "query"
            $Result | Should -Not -Match "SELECT"
        }
    }

    Context 'Volume control' {

        It 'collapses long arrays to a shape summary instead of every element' {
            $Rows = 1..50 | ForEach-Object { [PSCustomObject]@{ Id = $_; DisplayName = "Person-$_" } }
            $Result = ConvertTo-RedactedLogString -InputObject @{ Rows = $Rows }

            $Result | Should -Match "Array\[50\]"
            $Result | Should -Not -Match "Person-42"
        }

        It 'keeps short arrays intact so small payloads stay readable' {
            $Result = ConvertTo-RedactedLogString -InputObject @{ Methods = @("GET", "POST") }

            $Result | Should -Match "GET"
            $Result | Should -Match "POST"
        }

        It 'truncates very long strings' {
            $Long = "a" * 2000
            $Result = ConvertTo-RedactedLogString -InputObject @{ Note = $Long } -MaxStringLength 50

            $Result.Length | Should -BeLessThan 500
            $Result | Should -Match "truncated"
        }

        It 'stops at the depth limit rather than walking forever' {
            $Deep = @{ A = @{ B = @{ C = @{ D = @{ E = @{ F = @{ G = "deep-value-here" } } } } } } }
            $Result = ConvertTo-RedactedLogString -InputObject $Deep -MaxDepth 3

            $Result | Should -Not -Match "deep-value-here"
        }
    }

    Context 'Robustness' {

        It 'terminates on a self-referencing object instead of recursing forever' {
            # Live WPF/session objects are cyclic; the walker must not hang the UI thread.
            $Cyclic = @{ Name = "root" }
            $Cyclic["Self"] = $Cyclic

            $Result = ConvertTo-RedactedLogString -InputObject $Cyclic

            $Result | Should -Match "root"
            $Result | Should -Match "circular reference"
        }

        It 'handles $null without throwing' {
            { ConvertTo-RedactedLogString -InputObject $null } | Should -Not -Throw
        }

        It 'handles a plain string without throwing' {
            ConvertTo-RedactedLogString -InputObject "just text" | Should -Match "just text"
        }

        It 'preserves non-sensitive diagnostic values' {
            $Result = ConvertTo-RedactedLogString -InputObject @{
                Uri                = "https://tenant.omada.cloud/odata"
                Method             = "POST"
                AuthenticationType = "Basic"
            }

            $Result | Should -Match "tenant.omada.cloud"
            $Result | Should -Match "POST"
        }

        It 'always returns a string, never $null' {
            ConvertTo-RedactedLogString -InputObject @{} | Should -BeOfType [string]
        }
    }
}
