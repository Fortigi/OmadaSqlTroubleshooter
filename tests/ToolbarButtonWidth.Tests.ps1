#Requires -Version 7.0
# A toolbar button keeps one width while its label changes (Execute / Cancel, Connect / Disconnect,
# Grid / Text). Every label the code can put on a toolbar button must already be in the markup as a
# hidden placeholder next to it (ToolbarTextPlaceholderStyle in MainFormTabContent.xaml), because that
# is what reserves the space. Parsed from the files, so this runs in the headless lane.

BeforeDiscovery {
    $Root = Split-Path -Path $PSScriptRoot -Parent
    $Source = (Get-ChildItem -Path ([System.IO.Path]::Combine($Root, "src", "Lib")) -Recurse -Filter *.ps1 | ForEach-Object { Get-Content -Path $_.FullName -Raw }) -join "`n"

    # Labels set with Set-ButtonText, and those of the Grid / Text button's look table.
    $Script:CodeLabel = @([regex]::Matches($Source, '\.(Button\w+Text)\s*\|\s*Set-ButtonText\s+-Value\s+"([^"]+)"') | ForEach-Object {
            @{ Name = $_.Groups[1].Value; Label = $_.Groups[2].Value -replace "_", "" }
        })
    $Script:CodeLabel += @([regex]::Matches($Source, 'Label\s*=\s*"([^"]+)"\s*;\s*ToolTip\s*=\s*"Results to') | ForEach-Object {
            @{ Name = "ButtonResultOutputModeText"; Label = $_.Groups[1].Value }
        })
}

BeforeAll {
    $Root = Split-Path -Path $PSScriptRoot -Parent
    [xml]$Script:Xaml = Get-Content -Path ([System.IO.Path]::Combine($Root, "src", "Lib", "ui", "MainFormTabContent.xaml")) -Raw
    $Script:XNs = "http://schemas.microsoft.com/winfx/2006/xaml"
}

Describe 'Toolbar button width' -Tag 'Unit' {
    It 'Should find the labels the code sets (Execute, Connect, Grid / Text at least)' -ForEach @(@{ Count = $Script:CodeLabel.Count }) {
        $Count | Should -BeGreaterOrEqual 6
    }

    It 'Should reserve the width of "<Label>" next to <Name>' -ForEach $Script:CodeLabel {
        $Text = @($Script:Xaml.SelectNodes("//*[local-name()='AccessText']") | Where-Object { $_.GetAttribute("Name", $Script:XNs) -eq $Name })
        $Text.Count | Should -Be 1
        if ($Text[0].GetAttribute("Visibility") -eq "Collapsed") {
            # An icon-only button: its label is never drawn, so it cannot change the width.
            return
        }

        $Placeholder = @($Text[0].ParentNode.ChildNodes | Where-Object { $_.LocalName -eq "TextBlock" -and $_.GetAttribute("Style") -eq "{StaticResource ToolbarTextPlaceholderStyle}" } | ForEach-Object { $_.GetAttribute("Text") })
        $Text[0].ParentNode.LocalName | Should -Be "Grid"
        $Placeholder | Should -Contain $Label
    }

    It 'Should keep the placeholders out of sight' {
        $Style = $Script:Xaml.SelectSingleNode("//*[local-name()='Style' and @*[local-name()='Key']='ToolbarTextPlaceholderStyle']")
        ($Style.ChildNodes | Where-Object { $_.GetAttribute("Property") -eq "Visibility" }).GetAttribute("Value") | Should -Be "Hidden"
    }
}
