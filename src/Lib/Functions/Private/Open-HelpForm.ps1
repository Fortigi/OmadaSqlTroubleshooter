function Open-HelpForm {
    <#
    .SYNOPSIS
        Help > Help and keyboard shortcuts: the shortcuts (Get-KeyboardShortcut), links to the
        project and the PowerShell Gallery, and reporting a bug or requesting a feature on GitHub.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    try {
        $Script:HelpForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\HelpForm.xaml")
        if ($null -ne $Script:MainForm -and $null -ne $Script:MainForm.Definition) {
            $Script:HelpForm.Definition.Owner = $Script:MainForm.Definition
        }
        Import-EventObjects -ClassName "HelpForm"

        $Script:HelpForm.Elements.DataGridShortcuts.ItemsSource = @(Get-KeyboardShortcut)
        $Script:HelpForm.Elements.TextBlockHelpVersion.Text = (Get-AboutText -Version $Script:RunTimeConfig.ApplicationVersion -Year (Get-Date).Year).Version

        # Only for a version GitHub has a release of (Get-GitHubReleaseLink).
        $Private:ReleaseLink = Get-GitHubReleaseLink
        if (-not [string]::IsNullOrWhiteSpace($Private:ReleaseLink)) {
            $Script:HelpForm.Elements.ButtonHelpRelease.ToolTip = $Private:ReleaseLink
            $Script:HelpForm.Elements.ButtonHelpRelease.Visibility = "Visible"
        }

        # As Open-ChoiceForm: ShowDialog pumps this thread's messages while it blocks, which could let
        # the WebView2 completion poll timer fire reentrantly.
        Suspend-WebViewCompletionPolling
        try {
            [void]$Script:HelpForm.Definition.ShowDialog()
        }
        finally {
            Resume-WebViewCompletionPolling
        }
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}

function Get-HelpLink {
    <#
    .SYNOPSIS
        The project's addresses the Help window links to.

    .PARAMETER Name
        Project, Gallery, Issues, Bug or Feature.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Project", "Gallery", "Issues", "Bug", "Feature")]
        [string]$Name
    )

    $Private:Project = "https://github.com/Fortigi/OmadaSqlTroubleshooter"
    switch ($Name) {
        "Project" { return $Private:Project }
        "Gallery" { return "https://www.powershellgallery.com/packages/OmadaSqlTroubleshooter" }
        "Issues" { return "{0}/issues" -f $Private:Project }
        "Bug" { return "{0}/issues/new?template=bug_report.yml" -f $Private:Project }
        "Feature" { return "{0}/issues/new?template=feature_request.yml" -f $Private:Project }
    }
}

function New-GitHubIssueUrl {
    <#
    .SYNOPSIS
        The address of a new GitHub issue from the repository's bug or feature form, with the
        versions a bug report asks for already filled in.

    .DESCRIPTION
        GitHub fills an issue form's fields from query parameters named after the field ids in
        .github/ISSUE_TEMPLATE/bug_report.yml. Only the version fields are filled - the module,
        OmadaWeb.PS, PowerShell and Windows - and only in the address the browser opens: nothing is
        sent anywhere until the user submits the issue on GitHub, where every field can still be
        changed. No tenant, user or query data is ever put in it.

        A version that is not known is left out rather than sent empty, so the form shows its own
        placeholder.

    .PARAMETER Kind
        Bug or Feature.

    .PARAMETER Version
        @{ module-version; omadaweb-ps-version; powershell-version; os-version }, for a bug.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Bug", "Feature")]
        [string]$Kind,

        [Parameter(Mandatory = $false)]
        [System.Collections.IDictionary]$Version = @{}
    )

    $Private:Url = Get-HelpLink -Name $Kind
    if ($Kind -ne "Bug") {
        return $Private:Url
    }

    foreach ($Private:Field in @("module-version", "omadaweb-ps-version", "powershell-version", "os-version")) {
        $Private:Value = [string]$Version[$Private:Field]
        if (-not [string]::IsNullOrWhiteSpace($Private:Value)) {
            $Private:Url += "&{0}={1}" -f $Private:Field, [System.Uri]::EscapeDataString($Private:Value.Trim())
        }
    }
    return $Private:Url
}

function Get-IssueVersionInfo {
    <#
    .SYNOPSIS
        The versions a bug report asks for, read from this session.

    .OUTPUTS
        [hashtable] @{ module-version; omadaweb-ps-version; powershell-version; os-version }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $Private:OmadaWeb = Get-Module -Name "OmadaWeb.PS" | Sort-Object -Property Version -Descending | Select-Object -First 1
    return @{
        "module-version"      = [string]$Script:RunTimeConfig.ApplicationVersion
        "omadaweb-ps-version" = $(if ($null -ne $Private:OmadaWeb) { [string]$Private:OmadaWeb.Version } else { "" })
        "powershell-version"  = [string]$PSVersionTable.PSVersion
        "os-version"          = [string][System.Environment]::OSVersion.VersionString
    }
}

function Open-GitHubIssue {
    <#
    .SYNOPSIS
        Opens a new bug report or feature request for the project on GitHub, in the browser.

    .PARAMETER Kind
        Bug or Feature.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Bug", "Feature")]
        [string]$Kind
    )

    $Private:Version = if ($Kind -eq "Bug") { Get-IssueVersionInfo } else { @{} }
    Open-HelpUrl -Url (New-GitHubIssueUrl -Kind $Kind -Version $Private:Version)
}

function Open-GitHubReleaseNotes {
    <#
    .SYNOPSIS
        Opens the running version's release page on GitHub, when it has one.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param()

    $Private:ReleaseLink = Get-GitHubReleaseLink
    if ([string]::IsNullOrWhiteSpace($Private:ReleaseLink)) {
        "Version {0} has no release on GitHub." -f $Script:RunTimeConfig.ApplicationVersion | Write-LogOutput -LogType WARNING
        return
    }
    Open-HelpUrl -Url $Private:ReleaseLink
}

function Open-HelpUrl {
    <#
    .SYNOPSIS
        Opens one of the project's addresses in the default browser.

    .DESCRIPTION
        Handed to the operating system to open, so only an https address on github.com or
        www.powershellgallery.com is opened; anything else is refused with a warning.

    .PARAMETER Url
        The address.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $Private:Uri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$Private:Uri) -or $Private:Uri.Scheme -ne "https" -or $Private:Uri.Host -notin @("github.com", "www.powershellgallery.com")) {
        "Not opening '{0}': not one of the project's addresses." -f $Url | Write-LogOutput -LogType WARNING
        return
    }

    "Opening {0}" -f $Url | Write-LogOutput -LogType DEBUG
    Start-Process -FilePath $Private:Uri.AbsoluteUri
}
