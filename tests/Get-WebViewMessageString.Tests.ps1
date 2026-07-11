BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Command = Join-Path $ParentPath -ChildPath "src\lib\functions\Private\Get-WebViewMessageString.ps1"
    . $Command
}

Describe 'Get-WebViewMessageString' {
    It 'returns the string for a string-posted message' {
        $MessageArgs = [PSCustomObject]@{ WebMessageAsJson = '"ignored"' }
        $MessageArgs | Add-Member -MemberType ScriptMethod -Name TryGetWebMessageAsString -Value { '{"type":"executeQuery"}' }
        Get-WebViewMessageString -MessageEventArgs $MessageArgs | Should -Be '{"type":"executeQuery"}'
    }

    It 'falls back to WebMessageAsJson for an object-posted message (TryGetWebMessageAsString throws)' {
        $MessageArgs = [PSCustomObject]@{ WebMessageAsJson = '{"type":"contentChanged"}' }
        $MessageArgs | Add-Member -MemberType ScriptMethod -Name TryGetWebMessageAsString -Value {
            throw [System.ArgumentException]::new("Value does not fall within the expected range.")
        }
        Get-WebViewMessageString -MessageEventArgs $MessageArgs | Should -Be '{"type":"contentChanged"}'
    }

    It 'returns null when the event args are null' {
        Get-WebViewMessageString -MessageEventArgs $null | Should -BeNullOrEmpty
    }

    It 'produces a value that ConvertFrom-Json can parse into the message type' {
        $MessageArgs = [PSCustomObject]@{ WebMessageAsJson = '{"type":"contentChanged"}' }
        $MessageArgs | Add-Member -MemberType ScriptMethod -Name TryGetWebMessageAsString -Value {
            throw [System.ArgumentException]::new("Value does not fall within the expected range.")
        }
        $Message = Get-WebViewMessageString -MessageEventArgs $MessageArgs
        ($Message | ConvertFrom-Json).type | Should -Be "contentChanged"
    }
}
