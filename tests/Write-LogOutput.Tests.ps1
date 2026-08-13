BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $FunctionPath = Join-Path $ParentPath -ChildPath "src\lib\functions\Private"
    . (Join-Path $FunctionPath -ChildPath "Write-LogOutput.ps1")
    . (Join-Path $FunctionPath -ChildPath "Protect-LogMessage.ps1")
    . (Join-Path $FunctionPath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $FunctionPath -ChildPath "Get-LogResultShape.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    # The secret material the acceptance criterion of issue #39 names explicitly.
    $Script:SecretPassword = "Sup3rSecret!"
    $Script:SecretBasicHeader = "b21hZGE6U3VwM3JTZWNyZXQh"
    $Script:SecretBearerCookie = "bearercookievalue9876"
    $Script:SecretSessionId = "sessionvalue1234"
}

Describe 'Write-LogOutput redaction' {

    BeforeEach {
        # Minimal stand-in for the ambient application state Write-LogOutput reads. VERBOSE2 is the
        # loudest level, so everything the app can emit is in scope; VerboseParameterSet suppresses
        # the Write-Verbose echo and LogToConsole the Write-Host echo, leaving AppLogObject as the
        # subject.
        $Script:RunTimeConfig = [PSCustomObject]@{
            ApplicationName     = "Test"
            VerboseParameterSet = $true
            Logging             = [PSCustomObject]@{
                LogLevelSetting = "VERBOSE2"
                LogToConsole    = $false
                AppLogObject    = [System.Collections.ObjectModel.ObservableCollection[string]]::new()
            }
        }
        $Script:Tabs = @()
        $Script:ActiveTabId = $null
        $Script:TextBoxLog = $null
    }

    Context 'A full request parameter set (issue #39 acceptance criterion)' {

        BeforeEach {
            $Credential = [PSCredential]::new("omada\svc_sql", (ConvertTo-SecureString $Script:SecretPassword -AsPlainText -Force))
            $RequestParameters = @{
                Uri                = "https://tenant.omada.cloud/OData/BuiltIn/C_P_SQLTROUBLESHOOTING"
                Method             = "POST"
                AuthenticationType = "Basic"
                Credential         = $Credential
                Headers            = @{
                    Authorization = "Basic {0}" -f $Script:SecretBasicHeader
                    Cookie        = "OISSession={0}; ASP.NET_SessionId={1}" -f $Script:SecretBearerCookie, $Script:SecretSessionId
                }
                Body               = @{ query = "SELECT * FROM dbo.Identity"; page = 1 }
            }

            "Parameters: {0}" -f (ConvertTo-RedactedLogString -InputObject $RequestParameters) | Write-LogOutput -LogType VERBOSE
            $Script:LogText = $Script:RunTimeConfig.Logging.AppLogObject -join "`r`n"
        }

        It 'actually logged something (guards against the test passing on an empty log)' {
            $Script:LogText | Should -Not -BeNullOrEmpty
            $Script:LogText | Should -Match "Parameters:"
        }

        It 'contains no part of the Basic authorization header' {
            $Script:LogText | Should -Not -Match $Script:SecretBasicHeader
        }

        It 'contains no bearer session cookie' {
            $Script:LogText | Should -Not -Match $Script:SecretBearerCookie
            $Script:LogText | Should -Not -Match $Script:SecretSessionId
        }

        It 'contains no credential password' {
            $Script:LogText | Should -Not -Match ([regex]::Escape($Script:SecretPassword))
        }

        It 'contains no request body content' {
            $Script:LogText | Should -Not -Match "SELECT"
        }

        It 'still contains the information that makes the log worth keeping' {
            $Script:LogText | Should -Match "tenant.omada.cloud"
            $Script:LogText | Should -Match "POST"
        }

        It 'reports which account authenticated, end to end through both redaction layers' {
            # The walker keeps the user name and the safety net must not strip it again.
            $Script:LogText | Should -Match "svc_sql"
        }
    }

    Context 'The safety net' {

        It 'masks a secret in free-form text that never went through ConvertTo-RedactedLogString' {
            # E.g. an exception message from a third-party module quoting the request it made.
            "Request failed. Authorization: Basic dW5yZWRhY3RlZFZhbHVl" | Write-LogOutput -LogType VERBOSE

            $LogText = $Script:RunTimeConfig.Logging.AppLogObject -join "`r`n"
            $LogText | Should -Not -Match "dW5yZWRhY3RlZFZhbHVl"
            $LogText | Should -Match "Request failed"
        }

        It 'leaves an ordinary message untouched' {
            "Retrieve query output, please wait..." | Write-LogOutput -LogType INFO

            ($Script:RunTimeConfig.Logging.AppLogObject -join "`r`n") | Should -Match "Retrieve query output, please wait\.\.\."
        }
    }

    Context 'Result sets' {

        It 'logs a result set as a shape, with no cell values' {
            $Rows = 1..25 | ForEach-Object { [PSCustomObject]@{ Id = $_; DisplayName = "Employee-$_"; Email = "user$_@contoso.com" } }

            "Result: {0}" -f (Get-LogResultShape -InputObject $Rows) | Write-LogOutput -LogType VERBOSE2

            $LogText = $Script:RunTimeConfig.Logging.AppLogObject -join "`r`n"
            $LogText | Should -Match "25 row"
            $LogText | Should -Match "DisplayName"
            $LogText | Should -Not -Match "contoso.com"
            $LogText | Should -Not -Match "Employee-"
        }
    }
}
