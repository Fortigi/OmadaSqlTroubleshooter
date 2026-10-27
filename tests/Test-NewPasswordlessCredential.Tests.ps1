#Requires -Version 7.0
BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Test-NewPasswordlessCredential.ps1")

    function New-TestCredential {
        param([string]$Name, [AllowEmptyString()][string]$Text)
        $Secure = if ($Text -eq "") { [securestring]::new() } else { ConvertTo-SecureString -String $Text -AsPlainText -Force }
        [System.Management.Automation.PSCredential]::new($Name, $Secure)
    }
}

Describe 'Test-NewPasswordlessCredential' {

    It 'is true when there was no credential before' {
        Test-NewPasswordlessCredential -Previous $null -Current (New-TestCredential "jdoe" "") | Should -BeTrue
    }

    It 'is true when the previous credential had a password' {
        Test-NewPasswordlessCredential -Previous (New-TestCredential "jdoe" "x") -Current (New-TestCredential "jdoe" "") | Should -BeTrue
    }

    It 'is true when the username changed' {
        Test-NewPasswordlessCredential -Previous (New-TestCredential "jdoe" "") -Current (New-TestCredential "asmith" "") | Should -BeTrue
    }

    It 'is false when the same username was already passwordless' {
        Test-NewPasswordlessCredential -Previous (New-TestCredential "jdoe" "") -Current (New-TestCredential "jdoe" "") | Should -BeFalse
    }

    It 'is false when the new credential has a password' {
        Test-NewPasswordlessCredential -Previous $null -Current (New-TestCredential "jdoe" "x") | Should -BeFalse
    }

    It 'is false when there is no new credential' {
        Test-NewPasswordlessCredential -Previous (New-TestCredential "jdoe" "") -Current $null | Should -BeFalse
    }
}
