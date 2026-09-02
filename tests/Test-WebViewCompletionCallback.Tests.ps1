BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path $Script:RepositoryRoot -ChildPath 'src\Lib\Functions\Private\Test-WebViewCompletionCallback.ps1')
}

Describe 'Test-WebViewCompletionCallback' -Tag 'Unit' {

    Context 'When there is nothing to invoke' {

        It 'Should reject a null callback' {
            # The regression this exists for. The syntax pass pushes its markers and has nothing to
            # run afterwards, so it queues no completion block; "& $null" then failed the whole Tick
            # handler with "The expression after '&' in a pipeline element produced an object that
            # was not valid", taking every other pending completion down with it.
            Test-WebViewCompletionCallback -Callback $null | Should -BeFalse
        }

        It 'Should reject values "&" cannot invoke' -ForEach @(
            @{ Case = 'an empty string'; Value = '' }
            @{ Case = 'a plain object'; Value = [PSCustomObject]@{ Name = 'not a callback' } }
            @{ Case = 'an integer'; Value = 42 }
            @{ Case = 'an empty array'; Value = @() }
        ) {
            Test-WebViewCompletionCallback -Callback $Value | Should -BeFalse -Because "$Case is not something '&' can invoke"
        }
    }

    Context 'When there is something to invoke' {

        It 'Should accept a script block' {
            Test-WebViewCompletionCallback -Callback { param($Pending) $Pending } | Should -BeTrue
        }

        It 'Should accept an empty script block' {
            # A caller that deliberately queues a no-op still gets it invoked; only the absence of a
            # callback is skipped.
            Test-WebViewCompletionCallback -Callback {} | Should -BeTrue
        }

        It 'Should accept a CommandInfo' {
            # "&" takes one, so the guard must not be the thing that refuses it.
            Test-WebViewCompletionCallback -Callback (Get-Command Get-Date) | Should -BeTrue
        }
    }

    Context 'Agreement with what the call operator actually accepts' {

        It 'Should be true exactly when "&" can invoke the value without throwing' {
            # Pins the guard to the operator's real behaviour rather than to a list someone
            # remembered, which is how the original bug got in.
            $Candidate = @(
                @{ Value = $null }
                @{ Value = '' }
                @{ Value = 42 }
                @{ Value = [PSCustomObject]@{ Name = 'x' } }
                @{ Value = { 'invoked' } }
                @{ Value = (Get-Command Get-Date) }
            )

            foreach ($Item in $Candidate) {
                $TypeName = if ($null -eq $Item.Value) { 'null' } else { $Item.Value.GetType().Name }

                $Invokable = $true
                try {
                    $null = & $Item.Value 2>$null
                }
                catch {
                    $Invokable = $false
                }

                Test-WebViewCompletionCallback -Callback $Item.Value | Should -Be $Invokable -Because "the guard must agree with '&' for [$TypeName]"
            }
        }
    }
}
