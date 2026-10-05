BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $FunctionPath = Join-Path $ParentPath -ChildPath "src\lib\functions\Private"
    . (Join-Path $FunctionPath -ChildPath "Write-LogOutput.ps1")
    . (Join-Path $FunctionPath -ChildPath "Protect-LogMessage.ps1")
    . (Join-Path $FunctionPath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $FunctionPath -ChildPath "Get-LogResultShape.ps1")
    # Write-LogOutput now asks Test-LogLevelThreshold what its level includes, and offers every line
    # to the session log file as well (issue #121). Both are on the path taken for every message, so
    # this suite needs the real ones rather than a stand-in that could disagree with them.
    . (Join-Path $FunctionPath -ChildPath "Test-LogLevelThreshold.ps1")
    . (Join-Path $FunctionPath -ChildPath "Get-SessionLogFileName.ps1")
    . (Join-Path $FunctionPath -ChildPath "Write-SessionLogFile.ps1")

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
        # No session log file in this suite: AppLogObject is the subject here, and the file's own
        # behaviour - including that it is redacted identically - is SessionLogFileRedaction.Tests.ps1.
        $Script:SessionLogFile = $null
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

Describe 'Write-LogOutput dialog values (issue #135)' {

    BeforeAll {
        # The WARNING branch sets the icon to a [System.Windows.Forms.MessageBoxIcon]. CI runs the
        # unit tests in a plain pwsh host, which does not load WinForms on its own - without this the
        # branch throws inside Write-LogOutput's own catch, no dialog call happens at all, and the
        # assertions below would "pass" for entirely the wrong reason. Mirrors the Add-Type in
        # Update-QueryList.Tests.ps1.
        Add-Type -AssemblyName System.Windows.Forms

        # $LogMessageDialog is local to Write-LogOutput, so the only place its finished values are
        # observable is the call it makes with them.
        function Show-LogMessageDialog {
            param(
                [string]$Text,
                [string]$Title,
                $Icon
            )
            $Script:DialogCall = [PSCustomObject]@{ Text = $Text; Title = $Title; Icon = $Icon }
        }
    }

    BeforeEach {
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
        $Script:SessionLogFile = $null
        $Script:DialogCall = $null
        # A visible main form is what selects the Show-LogMessageDialog path over the no-window
        # MessageBox one.
        $Script:MainForm = [PSCustomObject]@{ Definition = [PSCustomObject]@{ IsVisible = $true } }
    }

    AfterEach {
        $Script:MainForm = $null
    }

    It 'shows the dialog with the title and icon the WARNING branch set' {
        "Query did not return any results" | Write-LogOutput -LogType WARNING

        # Guards against a vacuous pass: with no call, nothing below proves anything.
        $Script:DialogCall | Should -Not -BeNullOrEmpty
        $Script:DialogCall.Title | Should -Be "Warning - Main"
        $Script:DialogCall.Icon | Should -Be ([System.Windows.Forms.MessageBoxIcon]::Warning)
        $Script:DialogCall.Text | Should -Match "^Warning:"
    }

    It 'initializes only the keys the function goes on to read' {
        # Issue #135: the initializer declared DialogTitle/DialogIcon, while every reader and writer
        # in the function uses .Title/.Icon on the same hashtable. Those two were therefore always
        # $null and never read - the shape that invites a future edit to set the wrong pair and
        # wonder why the dialog is blank.
        $Source = Get-Content -Path (Join-Path $FunctionPath -ChildPath "Write-LogOutput.ps1") -Raw

        $Source | Should -Not -Match 'DialogTitle'
        $Source | Should -Not -Match 'DialogIcon'
    }
}
