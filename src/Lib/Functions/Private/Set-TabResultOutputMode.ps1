# Results to Grid / Results to Text, per tab.
#
# The mode lives on the tab's own config (AppConfig.ResultOutputMode), so it is saved and restored with
# the tab by Save-TabSessions. The mode chosen last, on any tab, is also kept in the global config as
# DefaultResultOutputMode: that is what a new tab starts in.
#
# Switching never runs the query again. The data is already on the tab session - QueryResults for the
# grids, StatementResults for the text - so switching only changes which of the two the pane shows.

function Get-ResultOutputMode {
    <#
    .SYNOPSIS
    Resolves a stored mode to "Grid" or "Text".

    .DESCRIPTION
    A valid mode is returned as is, in its canonical casing. Anything else - null, empty, or a value
    from a hand-edited config - falls back to the global DefaultResultOutputMode, then to the schema
    default, then to "Grid".

    .PARAMETER Mode
    The stored mode.

    .OUTPUTS
    [string] "Grid" or "Text".
    #>
    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Mode
    )

    foreach ($Private:Candidate in @($Mode, $Script:AppGlobalConfig.DefaultResultOutputMode)) {
        if ($Private:Candidate -eq "Text") {
            return "Text"
        }

        if ($Private:Candidate -eq "Grid") {
            return "Grid"
        }
    }

    try {
        if ((Get-ConfigSchemaDefault -Property "DefaultResultOutputMode") -eq "Text") {
            return "Text"
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }

    return "Grid"
}

function Set-TabResultOutputMode {
    <#
    .SYNOPSIS
    Switches a tab's Results pane between grid and text.

    .DESCRIPTION
    Stores the mode on the tab's config, makes it the default for new tabs, and applies it to the
    pane. Ctrl+Shift+D and Ctrl+Shift+T name the mode they want, so a shortcut that reaches this
    twice (from the editor and from the window) leaves the same result.

    .PARAMETER TabSession
    The tab to switch. Defaults to the active tab.

    .PARAMETER Mode
    Grid or Text.

    .PARAMETER Toggle
    Switch to the other mode. What the toolbar button does.
    #>
    [CmdLetBinding(DefaultParameterSetName = "Mode")]
    param(
        $TabSession,
        [Parameter(Mandatory = $true, ParameterSetName = "Mode")]
        [ValidateSet("Grid", "Text")]
        [string]$Mode,
        [Parameter(Mandatory = $true, ParameterSetName = "Toggle")]
        [switch]$Toggle
    )

    try {
        $Private:Target = if ($null -ne $TabSession) { $TabSession } else { Get-ActiveTabSession }
        if ($null -eq $Private:Target -or $null -eq $Private:Target.AppConfig) {
            return
        }

        $Private:Current = Get-ResultOutputMode -Mode $Private:Target.AppConfig.ResultOutputMode
        $Private:NewMode = if ($Toggle) {
            if ($Private:Current -eq "Text") { "Grid" } else { "Text" }
        }
        else {
            $Mode
        }

        if ($null -eq $Private:Target.AppConfig.PSObject.Properties["ResultOutputMode"]) {
            $Private:Target.AppConfig | Add-Member -NotePropertyName "ResultOutputMode" -NotePropertyValue $null
        }

        $Private:Target.AppConfig.ResultOutputMode = $Private:NewMode

        # Written straight through to the global config file, so the next new tab - in this run or the
        # next - starts in the mode the user chose last.
        if ($Script:AppGlobalConfig.DefaultResultOutputMode -ne $Private:NewMode) {
            $Private:NewMode | Set-ConfigProperty -Property "DefaultResultOutputMode"
        }

        "Results to {0}." -f $Private:NewMode | Write-LogOutput -LogType VERBOSE

        Update-TabResultOutputView -TabSession $Private:Target
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}

function Update-TabResultOutputView {
    <#
    .SYNOPSIS
    Shows the tab's results the way its mode says: the grid stack, or the text output.

    .DESCRIPTION
    Called after a switch, after an execute, and when a tab is materialized. In text mode the text is
    rendered from the tab's StatementResults every time, so it always matches the grids.

    Back in grid mode the grid handlers and the sizing pass run again, on the dispatcher, the way the
    execute completion runs them. Grids bound while the stack was hidden were never laid out, so they
    have no handlers and no heights yet. Both passes are idempotent, so running them for grids that
    were already set up does no harm.

    Visibility is assigned by name ("Visible", "Collapsed"); WPF converts the string, and the headless
    tests can run without System.Windows.

    .PARAMETER TabSession
    Defaults to the active tab.

    .PARAMETER NoLayoutPass
    Skip the grid layout pass. The execute completion schedules its own right after binding.
    #>
    [CmdLetBinding()]
    param(
        $TabSession,
        [switch]$NoLayoutPass
    )

    try {
        $Private:Target = if ($null -ne $TabSession) { $TabSession } else { Get-ActiveTabSession }
        if ($null -eq $Private:Target -or $null -eq $Private:Target.Elements) {
            return
        }

        $Private:Elements = $Private:Target.Elements
        $Private:IsText = (Get-ResultOutputMode -Mode $Private:Target.AppConfig.ResultOutputMode) -eq "Text"

        if ($null -ne $Private:Elements.ButtonResultOutputMode) {
            if ($Private:IsText) {
                $Private:Elements.ButtonResultOutputMode.ToolTip = "Results to text (Ctrl+Shift+T). Click for results to grid (Ctrl+Shift+D)."
            }
            else {
                $Private:Elements.ButtonResultOutputMode.ToolTip = "Results to grid (Ctrl+Shift+D). Click for results to text (Ctrl+Shift+T)."
            }
        }

        if ($null -ne $Private:Elements.ButtonResultOutputModeImage) {
            $Private:Elements.ButtonResultOutputModeImage.Text = if ($Private:IsText) { [string][char]0xE8A5 } else { [string][char]0xE80A }
        }

        if ($null -ne $Private:Elements.ButtonResultOutputModeText) {
            $Private:Elements.ButtonResultOutputModeText.Text = if ($Private:IsText) { "Text" } else { "Grid" }
        }

        if ($null -ne $Private:Elements.TextBoxQueryResultText) {
            if ($Private:IsText) {
                $Private:Elements.TextBoxQueryResultText.Text = Format-QueryResultText -StatementResult @($Private:Target.StatementResults) -QueryName $Private:Target.StatementResultQueryName
                $Private:Elements.TextBoxQueryResultText.Visibility = "Visible"
            }
            else {
                # Emptied rather than kept: a large result held twice, once as rows and once as text,
                # is memory for nothing. It is rendered again on the next switch.
                $Private:Elements.TextBoxQueryResultText.Text = ""
                $Private:Elements.TextBoxQueryResultText.Visibility = "Collapsed"
            }
        }

        if ($null -ne $Private:Elements.ScrollViewerQueryResults) {
            $Private:Elements.ScrollViewerQueryResults.Visibility = if ($Private:IsText) { "Collapsed" } else { "Visible" }
        }

        if (-not $NoLayoutPass -and -not $Private:IsText -and @($Private:Target.QueryResults).Count -gt 0) {
            $Private:ResultsControl = $Private:Elements.ItemsControlQueryResults
            if ($null -ne $Private:ResultsControl -and $null -ne $Private:ResultsControl.Dispatcher) {
                # A bare [System.Action], not a closure: see the same call in Complete-ExecuteQueryResult
                # for why GetNewClosure loses the module's commands. The tab is resolved inside.
                [void]$Private:ResultsControl.Dispatcher.BeginInvoke(
                    [System.Windows.Threading.DispatcherPriority]::Background,
                    [System.Action] {
                        try {
                            $Private:LayoutTab = Get-ActiveTabSession
                            Register-QueryResultGridHandler -TabSession $Private:LayoutTab
                            Update-QueryResultStackLayout -TabSession $Private:LayoutTab
                        }
                        catch {
                            $_.Exception.Message | Write-LogOutput -LogType DEBUG
                        }
                    })
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}
