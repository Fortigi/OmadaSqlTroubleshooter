#Requires -Version 7.0
# Every toolbar button can be enabled.
#
# The implicit <Style TargetType="Button"> in MainFormTabContent.xaml sets IsEnabled to False, so a
# button is disabled from the moment the tab is built. It only becomes usable when its own markup says
# IsEnabled="True", or when code enables it: Set-SqlQueryFunctionState on connect, or a direct
# ".<Name>.IsEnabled = $true". The Grid/Text button had neither and could never be clicked.
#
# Parsed from the files rather than loaded into WPF, so this runs in the headless lane.

BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $Script:XamlPath = Join-Path $Script:RepositoryRoot "src\Lib\ui\MainFormTabContent.xaml"
    $Script:Namespace = @{
        x = "http://schemas.microsoft.com/winfx/2006/xaml"
        p = "http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    }

    [xml]$Script:Xaml = Get-Content -Path $Script:XamlPath -Raw

    $Script:SourceText = (Get-ChildItem -Path (Join-Path $Script:RepositoryRoot "src\Lib") -Recurse -Filter *.ps1 | ForEach-Object { Get-Content -Path $_.FullName -Raw }) -join "`n"

    # The names Set-SqlQueryFunctionState may enable: every entry whose AllowedStatusChange is not
    # "Disable".
    $Private:FunctionState = Get-Content -Path (Join-Path $Script:RepositoryRoot "src\Lib\Functions\Private\Set-SqlQueryFunctionState.ps1") -Raw
    $Script:EnabledOnConnect = @([regex]::Matches($Private:FunctionState, '"(\w+)"\s*=\s*@\{\s*AllowedStatusChange\s*=\s*"(\w+)"') |
            Where-Object { $_.Groups[2].Value -ne "Disable" } |
            ForEach-Object { $_.Groups[1].Value })

    $Script:Button = @(Select-Xml -Xml $Script:Xaml -XPath "//p:Button[@x:Name]" -Namespace $Script:Namespace | ForEach-Object {
            [pscustomobject]@{
                Name      = $_.Node.GetAttribute("Name", $Script:Namespace.x)
                IsEnabled = $_.Node.GetAttribute("IsEnabled")
            }
        })
}

Describe 'MainFormTabContent toolbar buttons' -Tag 'Unit' {

    It 'disables every button by default, which is why each one needs a way to be enabled' {
        # Guards the premise. If the implicit style stops disabling buttons, this test is the one to
        # revisit, not the one below.
        $Private:Style = Select-Xml -Xml $Script:Xaml -XPath "//p:Style[@TargetType='Button' and not(@x:Key)]/p:Setter[@Property='IsEnabled']" -Namespace $Script:Namespace
        $Private:Style.Node.GetAttribute("Value") | Should -Be "False"
    }

    It 'finds the toolbar buttons' {
        $Script:Button.Count | Should -BeGreaterThan 5
    }

    It 'gives <Name> a way to be enabled' -ForEach @(
        @(Select-Xml -Xml ([xml](Get-Content -Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "src\Lib\ui\MainFormTabContent.xaml") -Raw)) -XPath "//p:Button[@x:Name]" -Namespace @{
                x = "http://schemas.microsoft.com/winfx/2006/xaml"
                p = "http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            } | ForEach-Object { @{ Name = $_.Node.GetAttribute("Name", "http://schemas.microsoft.com/winfx/2006/xaml") } })
    ) {
        $Private:Entry = $Script:Button | Where-Object { $_.Name -eq $Name }
        $Private:EnabledInMarkup = $Private:Entry.IsEnabled -eq "True"
        $Private:EnabledOnConnect = $Name -in $Script:EnabledOnConnect
        $Private:EnabledInCode = $Script:SourceText -match ("\.{0}\.IsEnabled\s*=\s*\`$true" -f [regex]::Escape($Name))

        ($Private:EnabledInMarkup -or $Private:EnabledOnConnect -or $Private:EnabledInCode) | Should -BeTrue -Because "$Name is disabled by the implicit Button style and nothing enables it"
    }

    It 'enables the Grid/Text button in its markup, because switching modes needs no connection' {
        ($Script:Button | Where-Object { $_.Name -eq "ButtonResultOutputMode" }).IsEnabled | Should -Be "True"
    }
}
