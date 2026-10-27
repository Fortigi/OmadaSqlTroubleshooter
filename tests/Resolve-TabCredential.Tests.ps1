#Requires -Version 7.0
BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Resolve-TabCredential.ps1")

    # The password box hands over a SecureString; ConvertTo-SecureString refuses an empty string.
    function New-TestSecureString {
        param([AllowEmptyString()][string]$Text)
        if ($Text -eq "") { return [securestring]::new() }
        return ConvertTo-SecureString -String $Text -AsPlainText -Force
    }
}

Describe 'Resolve-TabCredential' {

    Context 'Username and password' {
        It 'creates a password credential for <Option>' -ForEach @(
            @{ Option = "Browser" }, @{ Option = "WebView2" }, @{ Option = "OAuth" }, @{ Option = "WebView2-InPrivate" }
        ) {
            $Result = Resolve-TabCredential -UserName "jdoe@example.com" -Password (New-TestSecureString "P@ssw0rd!") -AuthenticationOption $Option
            $Result.Mode | Should -Be "Password"
            $Result.Credential.UserName | Should -BeExactly "jdoe@example.com"
            $Result.Credential.GetNetworkCredential().Password | Should -BeExactly "P@ssw0rd!"
        }

        It 'creates a password credential for Browser on the Selenium engine' {
            $Result = Resolve-TabCredential -UserName "jdoe" -Password (New-TestSecureString "secret") -AuthenticationOption "Browser" -UseWebView2Auth $false
            $Result.Mode | Should -Be "Password"
        }
    }

    Context 'Username without password' {
        It 'creates a passwordless credential for <Option>' -ForEach @(
            @{ Option = "WebView2" }, @{ Option = "WebView2-InPrivate" }
        ) {
            $Result = Resolve-TabCredential -UserName "jdoe@example.com" -Password (New-TestSecureString "") -AuthenticationOption $Option
            $Result.Mode | Should -Be "Passwordless"
            $Result.Credential | Should -BeOfType ([System.Management.Automation.PSCredential])
            $Result.Credential.UserName | Should -BeExactly "jdoe@example.com"
            $Result.Credential.Password.Length | Should -Be 0
            $Result.Credential.GetNetworkCredential().Password | Should -BeNullOrEmpty
        }

        It 'treats a null password as no password' {
            $Result = Resolve-TabCredential -UserName "jdoe" -Password $null -AuthenticationOption "WebView2"
            $Result.Mode | Should -Be "Passwordless"
        }

        It 'creates a passwordless credential for <Option> when Browser runs on WebView2' -ForEach @(
            @{ Option = "Browser" }, @{ Option = "Browser-InPrivate" }
        ) {
            $Result = Resolve-TabCredential -UserName "jdoe" -Password (New-TestSecureString "") -AuthenticationOption $Option -UseWebView2Auth $true
            $Result.Mode | Should -Be "Passwordless"
        }

        It 'refuses <Option> on the Selenium engine, which would submit an empty password' -ForEach @(
            @{ Option = "Browser" }, @{ Option = "Browser-InPrivate" }
        ) {
            $Result = Resolve-TabCredential -UserName "jdoe" -Password (New-TestSecureString "") -AuthenticationOption $Option -UseWebView2Auth $false
            $Result.Mode | Should -Be "None"
            $Result.Credential | Should -BeNullOrEmpty
            $Result.Reason | Should -Match "WebView2"
        }

        It 'refuses <Option>, which needs the secret itself' -ForEach @(
            @{ Option = "OAuth" }, @{ Option = "Basic" }, @{ Option = "Windows" }
        ) {
            $Result = Resolve-TabCredential -UserName "client-id" -Password (New-TestSecureString "") -AuthenticationOption $Option -UseWebView2Auth $true
            $Result.Mode | Should -Be "None"
            $Result.Credential | Should -BeNullOrEmpty
            $Result.Reason | Should -Match "requires a password"
        }

        It 'refuses when no authentication option is selected' {
            $Result = Resolve-TabCredential -UserName "jdoe" -Password (New-TestSecureString "") -AuthenticationOption $null
            $Result.Mode | Should -Be "None"
            $Result.Credential | Should -BeNullOrEmpty
        }
    }

    Context 'No username' {
        It 'creates no credential, whatever the password' -ForEach @(
            @{ UserName = $null; Password = "secret" }, @{ UserName = ""; Password = "" }, @{ UserName = "  "; Password = "secret" }
        ) {
            $Result = Resolve-TabCredential -UserName $UserName -Password (New-TestSecureString $Password) -AuthenticationOption "WebView2"
            $Result.Mode | Should -Be "None"
            $Result.Credential | Should -BeNullOrEmpty
            $Result.Reason | Should -Be "Username is empty"
        }
    }
}
