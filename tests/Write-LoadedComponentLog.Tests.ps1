#Requires -Version 7.0
# The start-up record of what this session is actually running.
#
# Every hard problem in this application so far has turned on information that was not in the log:
# which OmadaWeb.PS is loaded, whether the WebView2 assemblies came from the verified bundle or the
# download cache, whether the optional ScriptDom parser is present. These tests hold that line - and
# hold the harder one, that diagnostics must never be the reason the application fails to start.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Write-LoadedComponentLog.ps1")

    $script:LogMessages = [System.Collections.Generic.List[object]]::new()
    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { $script:LogMessages.Add([pscustomobject]@{ LogType = $LogType; Message = [string]$InputObject }) }
    }

    function script:Get-LoggedText {
        return (@($script:LogMessages | ForEach-Object { $_.Message }) -join "`n")
    }

    function script:Initialize-ComponentLogState {
        $script:LogMessages.Clear()
        $Script:RunTimeConfig = @{ ApplicationName = "OmadaSqlTroubleshooter"; ApplicationVersion = "1.2.3.4" }
        $Script:WebView2Source = "BUNDLE"
        $Script:WebView2BasePath = "C:\Modules\OmadaSqlTroubleshooter\Bin\WebView2Dlls\win-x64"
        $Script:WebView2CorePath = $null
        $Script:WebView2WpfPath = $null
        $Script:WebView2WinFormsPath = $null
        $Script:WebView2LoaderPath = $null
        $Script:ScriptDomPath = $null
    }
}

Describe "Write-LoadedComponentLog" {
    BeforeEach { Initialize-ComponentLogState }

    It "records the application name and version" {
        Write-LoadedComponentLog

        Get-LoggedText | Should -Match "OmadaSqlTroubleshooter 1\.2\.3\.4"
    }

    It "records the loaded OmadaWeb.PS version and where it came from" {
        # The module whose version most often explains a difference in authentication behaviour
        # between two machines - and the one the background-worker session problem turned on.
        Write-LoadedComponentLog

        $Text = Get-LoggedText
        if ($null -ne (Get-Module -Name "OmadaWeb.PS")) {
            $Text | Should -Match "OmadaWeb\.PS: \d+"
        }
        else {
            $Text | Should -Match "OmadaWeb\.PS: not loaded"
        }
    }

    It "records whether WebView2 came from the bundle or a download" {
        # Source matters as much as version: which of the two folders is in use is not otherwise
        # visible anywhere in the log.
        Write-LoadedComponentLog

        Get-LoggedText | Should -Match "WebView2 assemblies resolved from the bundle at"
    }

    It "reports a real assembly's file version and location" {
        $Real = (Get-Process -Id $PID).MainModule.FileName   # any file that certainly exists
        $Script:ScriptDomPath = $Real

        Write-LoadedComponentLog

        Get-LoggedText | Should -Match "ScriptDom: .+ at '"
    }

    It "says plainly when an optional component is not there" {
        # ScriptDom is legitimately absent until first use. That is information, not an error, and
        # must not be logged as one.
        $Script:ScriptDomPath = Join-Path ([System.IO.Path]::GetTempPath()) "definitely-not-here.dll"

        Write-LoadedComponentLog

        Get-LoggedText | Should -Match "ScriptDom: not present at"
        @($script:LogMessages | Where-Object { $_.LogType -in @("ERROR", "FATAL") }).Count | Should -Be 0
    }

    It "does not throw, or log an error, when nothing is configured at all" {
        # The line that matters most: this runs during start-up, and a diagnostic must never be the
        # reason the application fails to start.
        $Script:RunTimeConfig = $null
        $Script:WebView2Source = $null
        $Script:WebView2BasePath = $null

        { Write-LoadedComponentLog } | Should -Not -Throw
        @($script:LogMessages | Where-Object { $_.LogType -in @("ERROR", "FATAL") }).Count | Should -Be 0
    }

    It "keeps logging the other components when one of them cannot be read" {
        # Guarded per component: one unreadable file must not cost the log every other line.
        $Script:ScriptDomPath = "\\?\this-is-not-a-valid-path"
        $Script:WebView2CorePath = (Get-Process -Id $PID).MainModule.FileName

        { Write-LoadedComponentLog } | Should -Not -Throw
        Get-LoggedText | Should -Match "WebView2\.Core: "
    }
}
