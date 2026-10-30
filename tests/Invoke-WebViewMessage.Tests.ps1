#Requires -Version 7.0
# Tests for acting on a message the Monaco editor posted (issue #185).

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $Script:PrivatePath = [System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private")
}

Describe 'Invoke-WebViewMessage' -Tag 'Unit' {
    # The body of the tab's WebMessageReceived handler. 'contentChanged' arrives on every keystroke,
    # so it must not pay for the logging every other message does.

    BeforeAll {
        . (Join-Path $Script:PrivatePath "Invoke-WebViewMessage.ps1")
        . (Join-Path $Script:PrivatePath "Get-WebViewMessageString.ps1")

        # The execute and save branches raise a WPF click; requestSchema does not.
        try { Add-Type -AssemblyName PresentationFramework -ErrorAction Stop } catch { }
        $script:HasWpf = $null -ne ('System.Windows.RoutedEventArgs' -as [type])

        $script:Logged = [System.Collections.Generic.List[string]]::new()
        $script:EventsShown = 0
        $script:ContentChanges = [System.Collections.Generic.List[object]]::new()
        $script:Actions = [System.Collections.Generic.List[string]]::new()

        function Write-LogOutput {
            param([Parameter(ValueFromPipeline = $true)]$Message, [string]$LogType = "INFO", $ErrorObject, [switch]$SkipDialog, [switch]$TabScoped)
            process { $script:Logged.Add([string]$Message) }
        }
        function Show-EventInfo {
            param([Parameter(ValueFromPipeline = $true)]$Item)
            process { $script:EventsShown++ }
        }
        function Invoke-EditorContentChanged { param($TabSession) $script:ContentChanges.Add($TabSession) }
        function Set-ActiveTabContext { param($TabSession) $script:Actions.Add("active:{0}" -f $TabSession.Id) }
        function Request-SqlSchemaForDatabase { param($DatabaseName) $script:Actions.Add("schema:$DatabaseName") }

        # The dispatcher runs the action straight away, which is what Dispatcher.Invoke does on the UI
        # thread the event is raised on.
        $Dispatcher = [PSCustomObject]@{}
        $Dispatcher | Add-Member -MemberType ScriptMethod -Name Invoke -Value { param($Action) $Action.Invoke() }
        $Button = { param($Name) $B = [PSCustomObject]@{ Name = $Name }; $B | Add-Member -MemberType ScriptMethod -Name RaiseEvent -Value { param($RoutedEventArgs) $script:Actions.Add("click:{0}" -f $this.Name) }; $B }
        $Script:MainForm = [PSCustomObject]@{
            Definition = [PSCustomObject]@{ Dispatcher = $Dispatcher }
            Elements   = [PSCustomObject]@{ ButtonExecuteQuery = (& $Button "execute"); ButtonSaveQuery = (& $Button "save") }
        }

        function New-Message {
            param([string]$Json)
            # An object posted from the page: WebMessageAsJson carries it as JSON, and
            # TryGetWebMessageAsString() - absent here - is the call that throws for it.
            return [PSCustomObject]@{ WebMessageAsJson = $Json }
        }

        $script:Tab = [PSCustomObject]@{ Id = "tab-1"; DisplayName = "Query" }
        $script:WebView = [PSCustomObject]@{}
    }

    BeforeEach {
        $script:Logged.Clear()
        $script:EventsShown = 0
        $script:ContentChanges.Clear()
        $script:Actions.Clear()
    }

    It 'Should hand contentChanged to Invoke-EditorContentChanged without logging anything' {
        Invoke-WebViewMessage -TabSession $script:Tab -WebViewSender $script:WebView -MessageEventArgs (New-Message '{"type":"contentChanged"}') -EventInfo ([System.EventArgs]::Empty)

        $script:ContentChanges.Count | Should -Be 1
        $script:ContentChanges[0] | Should -Be $script:Tab
        $script:Logged.Count | Should -Be 0 -Because "a line per keystroke costs UI-thread time even when DEBUG is filtered out"
        $script:EventsShown | Should -Be 0
    }

    It 'Should still log and route <Type>' -ForEach @(
        @{ Type = 'executeQuery'; Json = '{"type":"executeQuery","key":"F5"}'; Expected = @("active:tab-1", "click:execute") }
        @{ Type = 'saveQuery'; Json = '{"type":"saveQuery","key":"Ctrl+S"}'; Expected = @("active:tab-1", "click:save") }
        @{ Type = 'requestSchema'; Json = '{"type":"requestSchema","database":"Other"}'; Expected = @("active:tab-1", "schema:Other") }
    ) {
        if ($Type -ne 'requestSchema' -and -not $script:HasWpf) {
            Set-ItResult -Skipped -Because "WPF (PresentationFramework) is not available on this machine"
            return
        }

        Invoke-WebViewMessage -TabSession $script:Tab -WebViewSender $script:WebView -MessageEventArgs (New-Message $Json) -EventInfo ([System.EventArgs]::Empty)

        $script:EventsShown | Should -Be 1
        ($script:Logged -join "`n") | Should -Match "WebView2 message received"
        @($script:Actions) | Should -Be $Expected
        $script:ContentChanges.Count | Should -Be 0
    }

    It 'Should log a message type it does not know, and do nothing with it' {
        Invoke-WebViewMessage -TabSession $script:Tab -WebViewSender $script:WebView -MessageEventArgs (New-Message '{"type":"somethingNew"}') -EventInfo ([System.EventArgs]::Empty)

        ($script:Logged -join "`n") | Should -Match "WebView2 message received"
        $script:Actions.Count | Should -Be 0
        $script:ContentChanges.Count | Should -Be 0
    }
}
