# Results to Grid / Results to Text, per tab.
#
# The mode lives on the tab's own config (AppConfig.ResultOutputMode), so it is saved and restored with
# the tab by Save-TabSessions. The mode chosen last, on any tab, is also kept in the global config as
# DefaultResultOutputMode: that is what a new tab starts in.
#
# Switching never runs the query again. The data is already on the tab session - QueryResults for the
# grids, StatementResults for the text - so switching only changes which of the two the pane shows.
#
# The work is split over several small functions on purpose: the quality gate holds every unit to a
# cyclomatic and cognitive complexity of 15.

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

function Initialize-TabResultOutputMode {
    <#
    .SYNOPSIS
    Gives a tab config a resolved ResultOutputMode.

    .DESCRIPTION
    A tab saved before this setting existed, or a config built by a caller that does not know it,
    has no ResultOutputMode property, and assigning a property a [PSCustomObject] does not have
    throws. So the property is added when it is missing, then set to the resolved mode: the tab's
    own when it has a valid one, otherwise the default for new tabs.

    .PARAMETER TabConfig
    The tab's AppConfig.
    #>
    [CmdLetBinding()]
    param(
        $TabConfig
    )

    if ($null -eq $TabConfig) {
        return
    }

    if ($null -eq $TabConfig.PSObject.Properties["ResultOutputMode"]) {
        $TabConfig | Add-Member -NotePropertyName "ResultOutputMode" -NotePropertyValue $null
    }

    $TabConfig.ResultOutputMode = Get-ResultOutputMode -Mode $TabConfig.ResultOutputMode
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

        Initialize-TabResultOutputMode -TabConfig $Private:Target.AppConfig

        $Private:NewMode = $Mode
        if ($Toggle) {
            $Private:NewMode = if ($Private:Target.AppConfig.ResultOutputMode -eq "Text") { "Grid" } else { "Text" }
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
    Called after a switch, after an execute, and when a tab is created. In text mode the text is
    rendered from the tab's StatementResults every time, so it always matches the grids.

    Back in grid mode the grid handlers and the sizing pass run again (Start-QueryResultGridLayoutPass).
    Grids bound while the stack was hidden were never laid out, so they have no handlers and no heights
    yet.

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

        $Private:IsText = (Get-ResultOutputMode -Mode $Private:Target.AppConfig.ResultOutputMode) -eq "Text"

        Set-ResultOutputModeButton -Elements $Private:Target.Elements -IsText:$Private:IsText
        Set-ResultOutputPane -TabSession $Private:Target -IsText:$Private:IsText

        if (-not ($NoLayoutPass -or $Private:IsText)) {
            Start-QueryResultGridLayoutPass -TabSession $Private:Target
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}

function Set-ResultOutputModeButton {
    <#
    .SYNOPSIS
    Makes the toolbar button show the tab's current mode.

    .PARAMETER Elements
    The tab's elements.

    .PARAMETER IsText
    The tab is in text mode.
    #>
    [CmdLetBinding()]
    param(
        $Elements,
        [switch]$IsText
    )

    $Private:Look = if ($IsText) {
        @{ Glyph = [string][char]0xE8A5; Label = "Text"; ToolTip = "Results to text (Ctrl+Shift+T). Click for results to grid (Ctrl+Shift+D)." }
    }
    else {
        @{ Glyph = [string][char]0xE80A; Label = "Grid"; ToolTip = "Results to grid (Ctrl+Shift+D). Click for results to text (Ctrl+Shift+T)." }
    }

    if ($null -ne $Elements.ButtonResultOutputMode) {
        $Elements.ButtonResultOutputMode.ToolTip = $Private:Look.ToolTip
    }

    if ($null -ne $Elements.ButtonResultOutputModeImage) {
        $Elements.ButtonResultOutputModeImage.Text = $Private:Look.Glyph
    }

    if ($null -ne $Elements.ButtonResultOutputModeText) {
        $Elements.ButtonResultOutputModeText.Text = $Private:Look.Label
    }
}

function Set-ResultOutputPane {
    <#
    .SYNOPSIS
    Shows the text output or the grid stack in the Results tab.

    .DESCRIPTION
    In text mode the text is rendered from the tab's StatementResults. In grid mode it is emptied
    rather than kept: a large result held twice, once as rows and once as text, is memory for nothing.

    .PARAMETER TabSession
    The tab.

    .PARAMETER IsText
    The tab is in text mode.
    #>
    [CmdLetBinding()]
    param(
        $TabSession,
        [switch]$IsText
    )

    $Private:Elements = $TabSession.Elements

    if ($null -ne $Private:Elements.TextBoxQueryResultText) {
        $Private:Text = ""
        if ($IsText) {
            $Private:Text = Format-QueryResultText -StatementResult @($TabSession.StatementResults) -QueryName $TabSession.StatementResultQueryName
        }

        $Private:Elements.TextBoxQueryResultText.Text = $Private:Text
        $Private:Elements.TextBoxQueryResultText.Visibility = if ($IsText) { "Visible" } else { "Collapsed" }
    }

    if ($null -ne $Private:Elements.ScrollViewerQueryResults) {
        $Private:Elements.ScrollViewerQueryResults.Visibility = if ($IsText) { "Collapsed" } else { "Visible" }
    }
}

function Start-QueryResultGridLayoutPass {
    <#
    .SYNOPSIS
    Registers the grid handlers and sizes the grid stack, once layout has realised the grids.

    .DESCRIPTION
    The same pass Complete-ExecuteQueryResult schedules after binding, for grids that were bound while
    the stack was hidden. Both Register-QueryResultGridHandler and Update-QueryResultStackLayout are
    idempotent, so running them for grids that were already set up does no harm.

    A bare [System.Action], not a closure: see the same call in Complete-ExecuteQueryResult for why
    GetNewClosure loses the module's commands. The tab is resolved inside the callback.

    .PARAMETER TabSession
    The tab.
    #>
    [CmdLetBinding()]
    param(
        $TabSession
    )

    if (@($TabSession.QueryResults).Count -eq 0) {
        return
    }

    $Private:ResultsControl = $TabSession.Elements.ItemsControlQueryResults
    if ($null -eq $Private:ResultsControl -or $null -eq $Private:ResultsControl.Dispatcher) {
        return
    }

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

function Invoke-ResultOutputModeShortcut {
    <#
    .SYNOPSIS
    Handles Ctrl+Shift+D (results to grid) and Ctrl+Shift+T (results to text) at window level.

    .DESCRIPTION
    While the editor has focus, Monaco handles both keys itself and posts setResultOutputMode, so they
    are only taken here when focus is elsewhere: the same split as F5. Every other key is left alone.

    .PARAMETER KeyEventArgs
    The PreviewKeyDown event arguments.

    .PARAMETER Modifiers
    The modifier keys held. Read from the keyboard when omitted; a parameter so tests can state it.

    .PARAMETER EditorHasFocus
    The editor has keyboard focus. Read from the WebView2 when omitted.
    #>
    [CmdLetBinding()]
    param(
        $KeyEventArgs,
        $Modifiers = [System.Windows.Input.Keyboard]::Modifiers,
        $EditorHasFocus = ($null -ne $Script:Webview.Object -and $Script:Webview.Object.IsKeyboardFocusWithin)
    )

    try {
        # Exactly Control (2) and Shift (4): ModifierKeys is a flags enum, so Ctrl+Shift+Alt+T is 7
        # and is left alone.
        $Private:Mode = @{ D = "Grid"; T = "Text" }[[string]$KeyEventArgs.Key]
        if ($null -eq $Private:Mode -or [int]$Modifiers -ne 6 -or $EditorHasFocus) {
            return
        }

        $KeyEventArgs.Handled = $true
        "Ctrl+Shift+{0} intercepted at MainForm level - results to {1}" -f $KeyEventArgs.Key, $Private:Mode | Write-LogOutput -LogType VERBOSE
        Set-TabResultOutputMode -TabSession (Get-ActiveTabSession) -Mode $Private:Mode
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}
