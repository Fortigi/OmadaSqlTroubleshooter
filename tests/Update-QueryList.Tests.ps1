#Requires -Version 7.0
# Regression tests for issue #65's second half: the query dropdown was openable on a tab the UI
# otherwise presented as disconnected.
#
# Pinned down rather than guessed: Update-QueryList ends by unconditionally setting
# ComboBoxSelectQuery, ButtonRefreshQueries, both "my queries" checkboxes and ButtonShowSqlSchema to
# IsEnabled = $true (src/Lib/Functions/Private/Update-QueryList.ps1, tail of the function). The
# WebView2 completion block in Initialize-WebViewForTab called it for EVERY tab whose editor
# finished loading, so for a restored tab it undid the Set-SqlQueryFunctionState -Status $false that
# Complete-TabMaterialization had just applied - and issued an authenticated request on the way.
#
# The request path runs through the real Invoke-OmadaPSWebRequestWrapper and the mock transport
# against a running mock instance, so "no request" is measured, not stubbed.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Test-ConnectionRequirements.ps1")
    . (Join-Path $PrivatePath -ChildPath "Invoke-OmadaPSWebRequestWrapper.ps1")
    . (Join-Path $PrivatePath -ChildPath "Update-QueryList.ps1")

    . (Join-Path $PSScriptRoot -ChildPath "mock\OmadaMockRouter.ps1")
    . (Join-Path $PSScriptRoot -ChildPath "mock\OmadaMockServer.ps1")
    . (Join-Path $PSScriptRoot -ChildPath "mock\Install-OmadaMockTransport.ps1")

    $script:Handle = New-OmadaMockServerHandle -BindAddress "127.0.0.1" -Port 0
    Install-OmadaMockTransport -MockBaseUrl $script:Handle.BaseUrl

    $Script:Tracer = [System.Diagnostics.Trace]

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { }
    }

    function Suspend-WebViewCompletionPolling { }

    function Resume-WebViewCompletionPolling { }

    function Set-SqlConnectionState {
        param([bool]$Status = $true)
    }

    function Set-EditorValue { }

    function Show-PopupWindow {
        param($Message)
        return $null
    }

    function Get-SqlTroubleShooterView { return $null }

    function New-QueryControlStub {
        <#
        The controls Set-SqlQueryFunctionState -Status $false leaves behind for a disconnected tab:
        emptied and disabled. A plain object stands in for the WPF control so the test is
        headless-safe; only Items/IsEnabled/Text are touched here.
        #>
        return [PSCustomObject]@{
            IsEnabled = $false
            Items     = [System.Collections.ArrayList]::new()
            Text      = $null
        }
    }

    function Initialize-QueryListTestState {
        param(
            [bool]$Connected
        )

        $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test"; ReconnectStatus = 3 }
        $Script:AppConfig = [PSCustomObject]@{
            BaseUrl              = "https://tenant.omada.cloud"
            MyCreatedQueriesOnly = $false
            MyUpdatedQueriesOnly = $false
            IdentityUserName     = $null
        }
        $Script:RunTimeData = @{
            SkipRetryRequest              = $false
            QueryListCache                = @{ QueryList = @(); LastRefresh = [datetime]::MinValue; TTL = 300 }
            CurrentSqlQuery               = [PSCustomObject]@{ DoId = $null; DisplayName = $null; FullName = $null }
            DataobjdlgAspxAttributeMapping = [PSCustomObject]@{
                SqlQueryCreatedBy = "CreatedBy"
                SqlQueryChangedBy = "ChangedBy"
                SqlQueryDoId      = "DoId"
            }
            RestMethodParam               = @{
                SessionKey          = "pool-under-test"
                AuthenticationType  = "Browser"
                ForceAuthentication = $false
            }
        }
        $Script:MainForm = @{
            Elements = @{
                TextBoxURL                         = [PSCustomObject]@{ Text = "https://tenant.omada.cloud" }
                ComboBoxSelectAuthenticationOption = [PSCustomObject]@{ SelectedItem = [PSCustomObject]@{ Content = "Browser" } }
                ComboBoxSelectQuery                = New-QueryControlStub
                ButtonRefreshQueries               = New-QueryControlStub
                CheckboxMyCreatedQueries           = New-QueryControlStub
                CheckboxMyUpdatedQueries           = New-QueryControlStub
                ButtonShowSqlSchema                = New-QueryControlStub
                TextBoxDisplayName                 = New-QueryControlStub
            }
        }
        $Script:ConnectionStatus = $Connected

        Clear-OmadaMockRequestLog
    }
}

AfterAll {
    if ($null -ne $script:Handle) { Stop-OmadaMockServerHandle -Handle $script:Handle }
}

Describe "Update-QueryList connection guard" {
    It "makes no request when the tab is not connected" {
        Initialize-QueryListTestState -Connected $false

        Update-QueryList

        (Get-OmadaMockRequestLog).Count | Should -Be 0
    }

    It "leaves the query controls disabled for a tab that is not connected" {
        Initialize-QueryListTestState -Connected $false

        Update-QueryList

        # The in-between state from issue #65: an openable query dropdown next to a Connect button.
        $Script:MainForm.Elements.ComboBoxSelectQuery.IsEnabled | Should -BeFalse
        $Script:MainForm.Elements.ButtonRefreshQueries.IsEnabled | Should -BeFalse
        $Script:MainForm.Elements.CheckboxMyCreatedQueries.IsEnabled | Should -BeFalse
        $Script:MainForm.Elements.CheckboxMyUpdatedQueries.IsEnabled | Should -BeFalse
        $Script:MainForm.Elements.ButtonShowSqlSchema.IsEnabled | Should -BeFalse
    }

    It "refreshes and enables the query controls for a connected tab" {
        Initialize-QueryListTestState -Connected $true

        Update-QueryList

        (Get-OmadaMockRequestLog -UriLike "*C_P_SQLTROUBLESHOOTING*").Count | Should -Be 1
        $Script:MainForm.Elements.ComboBoxSelectQuery.Items.Count | Should -BeGreaterThan 0
        $Script:MainForm.Elements.ComboBoxSelectQuery.IsEnabled | Should -BeTrue
        $Script:MainForm.Elements.ButtonRefreshQueries.IsEnabled | Should -BeTrue
    }
}
