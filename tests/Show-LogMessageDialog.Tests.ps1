#Requires -Version 7.0
# A warning or error dialog must not add anything to the output of the function that logged it.
# MessageBox.Show returns the button pressed; when that was not discarded, every function that logged a
# warning and then returned $null returned "OK" instead - the query manager's "Select a query first"
# was followed by its action running with an empty query id ("Cannot bind argument to parameter
# 'DoId' because it is an empty string").

BeforeAll {
    $PrivatePath = [System.IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Show-LogMessageDialog.ps1")

    function Suspend-WebViewCompletionPolling { }
    function Resume-WebViewCompletionPolling { }
    function Get-MainFormMessageBoxOwner { }
    function Restore-MainFormFocus { }
    function Limit-MessageBoxText { param($Text) $Text }
}

Describe 'Show-LogMessageDialog' -Tag 'Unit' {
    BeforeEach {
        Mock Show-WinFormsMessageBox { "OK" }
    }

    It 'Should show the dialog and give nothing back' {
        $Output = @(Show-LogMessageDialog -Text "Select a query first." -Title "Warning" -Icon "Warning")

        $Output.Count | Should -Be 0
        Should -Invoke Show-WinFormsMessageBox -Times 1 -Exactly -ParameterFilter { $Text -eq "Select a query first." -and $Title -eq "Warning" }
    }

    It 'Should leave a caller''s $null a $null' {
        function Get-Nothing { Show-LogMessageDialog -Text "x" -Title "y" -Icon "Warning"; return $null }

        $null -eq (Get-Nothing) | Should -BeTrue
    }

    It 'Should pass the owner when there is one, and release its handle afterwards' {
        $script:Owner = [PSCustomObject]@{ Name = "owner"; Released = 0 } | Add-Member -MemberType ScriptMethod -Name ReleaseHandle -Value { $this.Released++ } -PassThru
        Mock Get-MainFormMessageBoxOwner { $script:Owner }

        $null = Show-LogMessageDialog -Text "x" -Title "y" -Icon "Warning"

        Should -Invoke Show-WinFormsMessageBox -Times 1 -Exactly -ParameterFilter { $Owner.Name -eq "owner" }
        $script:Owner.Released | Should -Be 1
    }
}
