function Open-AboutForm {
    <#
    .SYNOPSIS
        Help > About: the startup splash screen's logo, name, version and copyright, in a window.

    .DESCRIPTION
        Modal on the main window; OK, Enter and Escape close it.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    try {
        $Script:AboutForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\AboutForm.xaml")
        if ($null -ne $Script:MainForm -and $null -ne $Script:MainForm.Definition) {
            $Script:AboutForm.Definition.Owner = $Script:MainForm.Definition
        }
        Import-EventObjects -ClassName "AboutForm"

        try {
            $Script:AboutForm.Elements.AboutLogoImage.Source = Get-Icon -Type Wpf
        }
        catch {
            "Failed to load application icon for the About window: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
        }

        $Private:Text = Get-AboutText -Version $Script:RunTimeConfig.ApplicationVersion -Year (Get-Date).Year
        $Script:AboutForm.Elements.AboutTitleLabel.Content = $Private:Text.Title
        $Script:AboutForm.Elements.AboutVersionLabel.Content = $Private:Text.Version

        # As Open-ChoiceForm: ShowDialog pumps this thread's messages while it blocks, which could let
        # the WebView2 completion poll timer fire reentrantly.
        Suspend-WebViewCompletionPolling
        try {
            [void]$Script:AboutForm.Definition.ShowDialog()
        }
        finally {
            Resume-WebViewCompletionPolling
        }
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}

function Get-AboutText {
    <#
    .SYNOPSIS
        The About window's text: the same version and copyright lines the splash screen shows.

    .PARAMETER Version
        The application version.

    .PARAMETER Year
        The current year, the end of the copyright range.

    .OUTPUTS
        [PSCustomObject] @{ Title; Version }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [int]$Year
    )

    return [PSCustomObject]@{
        Title   = "Omada Sql Troubleshooter"
        Version = "Version {0}`nFortigi (C) 2024-{1}" -f $Version, $Year
    }
}
