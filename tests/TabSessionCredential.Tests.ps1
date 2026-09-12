BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Save-TabSessions.ps1")
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-SecureStringFromText.ps1")
    # The tracer preamble of the function under test redacts its bound parameters.
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\ConvertTo-RedactedLogString.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    # Save-TabSessions reads $Script:Tabs / $Script:ActiveTabId / $Script:RunTimeConfig out of
    # module scope and logs through Write-LogOutput. The tab objects only ever have their
    # properties read, so plain PSCustomObjects stand in for the WPF controls - which keeps this
    # runnable on a headless CI agent, where System.Windows.* does not resolve.
    function Write-LogOutput {
        [CmdLetBinding()]
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { }
    }

    function New-StubTab {
        param(
            [string]$Id = (New-Guid).Guid,
            [string]$DisplayName = "Tab 1",
            [AllowNull()][string]$Password,
            [bool]$SavePassword = $true,
            [string]$UserName = "jdoe"
        )
        [PSCustomObject]@{
            Id          = $Id
            DisplayName = $DisplayName
            AppConfig   = [PSCustomObject]@{
                BaseUrl               = "https://tenant.omada.cloud"
                CurrentSqlQuery       = [PSCustomObject]@{ DoId = 42; DisplayName = "My Query"; FullName = "My Query - 42" }
                LastAuthentication    = "WebView2"
                UserName              = $UserName
                EntraApplicationIdUri = "api://app-id"
                EntraIdTenantId       = "11111111-1111-1111-1111-111111111111"
                MyCreatedQueriesOnly  = $false
                MyUpdatedQueriesOnly  = $false
                IdentityUserName      = "jdoe@example.com"
                CurrentDataConnection = [PSCustomObject]@{ DoId = 7; DisplayName = "Production"; FullName = "Production - 7" }
            }
            Elements    = [PSCustomObject]@{
                CheckboxSavePassword = [PSCustomObject]@{ IsChecked = $SavePassword }
                TextBoxPassword      = [PSCustomObject]@{ Password = $Password }
            }
        }
    }

    function Invoke-SaveTabSessions {
        param([object[]]$Tab, [string]$ActiveTabId)

        $AppDataFolder = Join-Path ([System.IO.Path]::GetTempPath()) ("osqCred_{0}" -f ([guid]::NewGuid().ToString("N")))
        $Script:RunTimeConfig = [PSCustomObject]@{
            ApplicationName = "Test"
            AppDataFolder   = $AppDataFolder
        }
        $Script:Tabs = $Tab
        $Script:ActiveTabId = $ActiveTabId

        Save-TabSessions

        Join-Path $AppDataFolder -ChildPath "config\tabs.clixml"
    }
}

Describe 'Tab session credential round-trip' {

    Context 'Save then load' {
        It 'should recover the exact password that was saved' {
            $Plain = "P@ssw0rd!"
            $Path = Invoke-SaveTabSessions -Tab @((New-StubTab -Password $Plain)) -ActiveTabId "a"
            try {
                $Loaded = Import-Clixml -Path $Path
                ($Loaded.Tabs[0].Password | Get-SecureStringFromText) | Should -BeExactly $Plain
            }
            finally {
                Remove-Item -Path (Split-Path (Split-Path $Path)) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'should round-trip a password full of non-ASCII characters' {
            $Plain = "Grüße-Ståle-日本語-Ω-🙂"
            $Path = Invoke-SaveTabSessions -Tab @((New-StubTab -Password $Plain)) -ActiveTabId "a"
            try {
                ((Import-Clixml -Path $Path).Tabs[0].Password | Get-SecureStringFromText) | Should -BeExactly $Plain
            }
            finally {
                Remove-Item -Path (Split-Path (Split-Path $Path)) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'should round-trip a password containing quotes, backticks and XML metacharacters' {
            # Clixml is XML, so a password with < > & " ' in it is exactly where a naive
            # serializer would corrupt or truncate the value.
            $Plain = 'a<b>c&d"e''f`g$h'
            $Path = Invoke-SaveTabSessions -Tab @((New-StubTab -Password $Plain)) -ActiveTabId "a"
            try {
                ((Import-Clixml -Path $Path).Tabs[0].Password | Get-SecureStringFromText) | Should -BeExactly $Plain
            }
            finally {
                Remove-Item -Path (Split-Path (Split-Path $Path)) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'should round-trip a long password' {
            $Plain = -join (1..200 | ForEach-Object { [char](65 + ($_ % 26)) })
            $Path = Invoke-SaveTabSessions -Tab @((New-StubTab -Password $Plain)) -ActiveTabId "a"
            try {
                ((Import-Clixml -Path $Path).Tabs[0].Password | Get-SecureStringFromText) | Should -BeExactly $Plain
            }
            finally {
                Remove-Item -Path (Split-Path (Split-Path $Path)) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'should rebuild the PSCredential the way New-TabSession does' {
            # New-TabSession.ps1 does not only call Get-SecureStringFromText; it also feeds the
            # stored blob straight into a PSCredential. Both readers must agree.
            $Plain = "P@ssw0rd!"
            $Path = Invoke-SaveTabSessions -Tab @((New-StubTab -Password $Plain -UserName "jdoe")) -ActiveTabId "a"
            try {
                $Loaded = Import-Clixml -Path $Path
                $Credential = [System.Management.Automation.PSCredential]::new(
                    $Loaded.Tabs[0].UserName,
                    ($Loaded.Tabs[0].Password | ConvertTo-SecureString)
                )
                $Credential.UserName | Should -Be "jdoe"
                $Credential.GetNetworkCredential().Password | Should -BeExactly $Plain
            }
            finally {
                Remove-Item -Path (Split-Path (Split-Path $Path)) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'should keep every tab with its own password when several tabs are saved' {
            $Path = Invoke-SaveTabSessions -Tab @(
                (New-StubTab -Id "one" -DisplayName "One" -Password "first-secret")
                (New-StubTab -Id "two" -DisplayName "Two" -Password "second-secret")
            ) -ActiveTabId "two"
            try {
                $Loaded = Import-Clixml -Path $Path
                $Loaded.ActiveTabId | Should -Be "two"
                ($Loaded.Tabs | Where-Object { $_.Id -eq "one" }).Password | Get-SecureStringFromText | Should -BeExactly "first-secret"
                ($Loaded.Tabs | Where-Object { $_.Id -eq "two" }).Password | Get-SecureStringFromText | Should -BeExactly "second-secret"
            }
            finally {
                Remove-Item -Path (Split-Path (Split-Path $Path)) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Nothing readable is written to disk' {
        It 'should not write the password anywhere in the saved file' {
            # The negative criterion. A plain substring search over the raw bytes - not over the
            # deserialized object - is what actually proves the file is not holding plaintext.
            $Plain = "Sup3rSecretValue-DoNotLeak"
            $Path = Invoke-SaveTabSessions -Tab @((New-StubTab -Password $Plain)) -ActiveTabId "a"
            try {
                $Raw = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($Path))
                $Raw | Should -Not -Match ([regex]::Escape($Plain))

                # UTF-16 is how a .NET string reaches a file that was written another way, so check
                # that spelling of the same secret too.
                $Utf16 = [System.Text.Encoding]::Unicode.GetString([System.IO.File]::ReadAllBytes($Path))
                $Utf16 | Should -Not -Match ([regex]::Escape($Plain))
            }
            finally {
                Remove-Item -Path (Split-Path (Split-Path $Path)) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'should store the password as a DPAPI blob, not as a live SecureString' {
            # Import-Clixml must hand back the encrypted string, because New-TabSession pipes it
            # into ConvertTo-SecureString. A [SecureString] here would break that read path.
            $Path = Invoke-SaveTabSessions -Tab @((New-StubTab -Password "P@ssw0rd!")) -ActiveTabId "a"
            try {
                $Stored = (Import-Clixml -Path $Path).Tabs[0].Password
                $Stored | Should -BeOfType [string]
                $Stored | Should -Match '^[0-9a-fA-F]+$'
                $Stored.Length | Should -BeGreaterThan 64
            }
            finally {
                Remove-Item -Path (Split-Path (Split-Path $Path)) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'should write no password at all when Save password is unchecked' {
            $Path = Invoke-SaveTabSessions -Tab @((New-StubTab -Password "not-to-be-kept" -SavePassword $false)) -ActiveTabId "a"
            try {
                $Loaded = Import-Clixml -Path $Path
                $Loaded.Tabs[0].Password | Should -BeNullOrEmpty
                $Loaded.Tabs[0].SavePassword | Should -Be $false

                $Raw = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($Path))
                $Raw | Should -Not -Match "not-to-be-kept"
            }
            finally {
                Remove-Item -Path (Split-Path (Split-Path $Path)) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'should write no password when the box is ticked but the field is blank' {
            $Path = Invoke-SaveTabSessions -Tab @((New-StubTab -Password "   " -SavePassword $true)) -ActiveTabId "a"
            try {
                (Import-Clixml -Path $Path).Tabs[0].Password | Should -BeNullOrEmpty
            }
            finally {
                Remove-Item -Path (Split-Path (Split-Path $Path)) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Get-SecureStringFromText' {
        It 'should refuse a blob it cannot decrypt rather than returning something wrong' {
            { "not-a-dpapi-blob" | Get-SecureStringFromText } | Should -Throw "*Is the password file correct?*"
        }

        It 'should refuse a missing value rather than returning an empty password' {
            { Get-SecureStringFromText -SecureString $null } | Should -Throw
        }
    }
}
