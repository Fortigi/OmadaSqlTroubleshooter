#Requires -Version 7.0
# Results to Grid / Results to Text, per tab. The state half - the mode on the tab's config, the
# global default for new tabs, and which control the pane shows - runs headless against stand-ins.
# Visibility is assigned by name, which is what lets these run without System.Windows.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-SingleLineSqlText.ps1")
    . (Join-Path $PrivatePath -ChildPath "Format-QueryResultText.ps1")
    . (Join-Path $PrivatePath -ChildPath "Set-TabResultOutputMode.ps1")

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog,
            [switch]$TabScoped
        )
        process { }
    }

    function Get-ConfigSchemaDefault {
        param([string]$Property)
        return "Grid"
    }

    # Records the global write instead of touching the config file.
    function Set-ConfigProperty {
        param(
            [Parameter(ValueFromPipeline = $true)]$Value,
            [string]$Property
        )
        process {
            $script:GlobalWrite.Add(("{0}={1}" -f $Property, $Value))
            $Script:AppGlobalConfig.$Property = $Value
        }
    }

    function Get-ActiveTabSession { return $script:TestTabSession }

    function script:New-TestTabSession {
        param($Mode = $null)

        return [pscustomobject]@{
            Id                       = "tab-A"
            AppConfig                = [pscustomobject]@{ ResultOutputMode = $Mode }
            QueryResults             = [System.Collections.Generic.List[object]]::new()
            StatementResults         = [System.Collections.Generic.List[object]]::new()
            StatementResultQueryName = "My query"
            Elements                 = @{
                ButtonResultOutputMode      = [pscustomobject]@{ ToolTip = "" }
                ButtonResultOutputModeImage = [pscustomobject]@{ Text = "" }
                ButtonResultOutputModeText  = [pscustomobject]@{ Text = "" }
                TextBoxQueryResultText      = [pscustomobject]@{ Text = "previous"; Visibility = "Collapsed" }
                ScrollViewerQueryResults    = [pscustomobject]@{ Visibility = "Visible" }
            }
        }
    }
}

Describe 'Get-ResultOutputMode' -Tag 'Unit' {

    BeforeEach {
        $Script:AppGlobalConfig = [pscustomobject]@{ DefaultResultOutputMode = $null }
    }

    It 'keeps a valid mode, in its canonical casing' {
        Get-ResultOutputMode -Mode "Text" | Should -BeExactly "Text"
        Get-ResultOutputMode -Mode "grid" | Should -BeExactly "Grid"
    }

    It 'falls back to the global default for <Case>' -ForEach @(
        @{ Case = "no mode"; Value = $null },
        @{ Case = "an unknown mode"; Value = "File" }
    ) {
        $Script:AppGlobalConfig.DefaultResultOutputMode = "Text"

        Get-ResultOutputMode -Mode $Value | Should -BeExactly "Text"
    }

    It 'falls back to Grid when nothing is set' {
        Get-ResultOutputMode -Mode $null | Should -BeExactly "Grid"
    }
}

Describe 'Set-TabResultOutputMode' -Tag 'Unit' {

    BeforeEach {
        $Script:AppGlobalConfig = [pscustomobject]@{ DefaultResultOutputMode = "Grid" }
        $script:GlobalWrite = [System.Collections.Generic.List[string]]::new()
        $script:TestTabSession = New-TestTabSession -Mode "Grid"
    }

    It 'stores the mode on the tab and makes it the default for new tabs' {
        Set-TabResultOutputMode -TabSession $script:TestTabSession -Mode Text

        $script:TestTabSession.AppConfig.ResultOutputMode | Should -BeExactly "Text"
        @($script:GlobalWrite) | Should -Be @("DefaultResultOutputMode=Text")
    }

    It 'does not write the global config when the default is already that mode' {
        Set-TabResultOutputMode -TabSession $script:TestTabSession -Mode Grid

        $script:GlobalWrite.Count | Should -Be 0
    }

    It 'switches to the other mode with -Toggle' {
        Set-TabResultOutputMode -TabSession $script:TestTabSession -Toggle
        $script:TestTabSession.AppConfig.ResultOutputMode | Should -BeExactly "Text"

        Set-TabResultOutputMode -TabSession $script:TestTabSession -Toggle
        $script:TestTabSession.AppConfig.ResultOutputMode | Should -BeExactly "Grid"
    }

    It 'adds the mode to a tab config that predates it' {
        $script:TestTabSession.AppConfig = [pscustomobject]@{ BaseUrl = "https://example.invalid" }

        Set-TabResultOutputMode -TabSession $script:TestTabSession -Mode Text

        $script:TestTabSession.AppConfig.ResultOutputMode | Should -BeExactly "Text"
    }

    It 'accepts only Grid and Text' {
        $Private:Parameter = (Get-Command Set-TabResultOutputMode).Parameters["Mode"]
        $Private:ValidValues = ($Private:Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues

        @($Private:ValidValues) | Should -Be @("Grid", "Text")
    }
}

Describe 'Update-TabResultOutputView' -Tag 'Unit' {

    BeforeEach {
        $Script:AppGlobalConfig = [pscustomobject]@{ DefaultResultOutputMode = "Grid" }
    }

    It 'shows the text output, rendered from the stored results, in text mode' {
        $script:TestTabSession = New-TestTabSession -Mode "Text"
        $script:TestTabSession.StatementResults.Add([pscustomobject]@{ Ordinal = 1; DisplayText = "SELECT 1"; Rows = @([pscustomobject]@{ A = 1 }); RowCount = 1 })

        Update-TabResultOutputView -TabSession $script:TestTabSession

        $Private:Elements = $script:TestTabSession.Elements
        $Private:Elements.TextBoxQueryResultText.Visibility | Should -Be "Visible"
        $Private:Elements.ScrollViewerQueryResults.Visibility | Should -Be "Collapsed"
        $Private:Elements.TextBoxQueryResultText.Text | Should -BeLike "Statement: 1*Query name: My query*Query: SELECT 1*(1 row(s) affected)*"
        $Private:Elements.ButtonResultOutputModeText.Text | Should -Be "Text"
        $Private:Elements.ButtonResultOutputModeImage.Text | Should -Be ([string][char]0xE8A5)
    }

    It 'shows the grid stack and empties the text in grid mode' {
        $script:TestTabSession = New-TestTabSession -Mode "Grid"

        Update-TabResultOutputView -TabSession $script:TestTabSession

        $Private:Elements = $script:TestTabSession.Elements
        $Private:Elements.TextBoxQueryResultText.Visibility | Should -Be "Collapsed"
        $Private:Elements.TextBoxQueryResultText.Text | Should -BeExactly ""
        $Private:Elements.ScrollViewerQueryResults.Visibility | Should -Be "Visible"
        $Private:Elements.ButtonResultOutputModeText.Text | Should -Be "Grid"
        $Private:Elements.ButtonResultOutputModeImage.Text | Should -Be ([string][char]0xE80A)
    }
}
