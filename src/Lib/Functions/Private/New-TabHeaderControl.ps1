function New-TabHeaderControl {
    <#
    .SYNOPSIS
    Builds a tab header: a title TextBlock that stretches across the tab and a close ("x") button
    pinned to the far right, matching this codebase's pattern of building/mutating WPF controls in
    code. The header is a 2-column Grid (title = star width, close = auto) with a MinWidth so the
    close button always sits at the right edge rather than immediately after the title text (the
    right-alignment bug). Visual styling (active/inactive tab look, close-button hover) comes from
    the TabItem template and TabCloseButtonStyle defined in MainForm.xaml.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession
    )
    try {
        # Logging the full $PSBoundParameters here would dump the entire $TabSession object graph
        # (WPF elements, AppConfig) into the trace log - log a stable identifier instead.
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ("TabSession={0} ({1})" -f $TabSession.Id, $TabSession.DisplayName)))

        $Grid = New-Object System.Windows.Controls.Grid
        # A Grid with no Background is hit-test transparent, so mouse events fall through it to the
        # TabItem - which is why tab-drag handlers had to live on the TabItem and there caught mouse
        # moves in the tab CONTENT too (hijacking textbox selection). Give the header its own
        # transparent-but-hit-testable background so the drag handlers can live on the header alone
        # (see New-TabSession) and never see content interactions.
        $Grid.Background = [System.Windows.Media.Brushes]::Transparent
        # MaxWidth caps a tab's natural width; the single-row ShrinkingTabPanel shrinks tabs below
        # this (down to a floor) when there are too many to fit on one row, and the title's
        # CharacterEllipsis trimming truncates the text as the tab narrows.
        $Grid.MinWidth = 40
        $Grid.MaxWidth = 240
        $Grid.Height = 22

        $TitleColumn = New-Object System.Windows.Controls.ColumnDefinition
        $TitleColumn.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $CloseColumn = New-Object System.Windows.Controls.ColumnDefinition
        $CloseColumn.Width = [System.Windows.GridLength]::Auto
        $Grid.ColumnDefinitions.Add($TitleColumn)
        $Grid.ColumnDefinitions.Add($CloseColumn)

        $TitleText = New-Object System.Windows.Controls.TextBlock
        $TitleText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $TitleText.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        $TitleText.Margin = New-Object System.Windows.Thickness(2, 0, 8, 0)
        [System.Windows.Controls.Grid]::SetColumn($TitleText, 0)

        $CloseButton = New-Object System.Windows.Controls.Button
        $CloseButton.Content = [char]0x2715
        $CloseButton.ToolTip = "Close tab"
        $CloseButton.IsEnabled = $true
        $CloseButton.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $CloseButton.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
        [System.Windows.Controls.Grid]::SetColumn($CloseButton, 1)

        # Prefer the shared XAML style (flat button, hover highlight); fall back to bare properties
        # if the resource is not available for any reason so the button still works.
        $CloseStyle = $null
        try {
            $CloseStyle = $Script:MainForm.Definition.TryFindResource("TabCloseButtonStyle")
        }
        catch {
            $CloseStyle = $null
        }
        if ($null -ne $CloseStyle) {
            $CloseButton.Style = $CloseStyle
        }
        else {
            $CloseButton.Width = 16
            $CloseButton.Height = 16
            $CloseButton.Padding = New-Object System.Windows.Thickness(0)
            $CloseButton.FontSize = 10
            $CloseButton.Background = [System.Windows.Media.Brushes]::Transparent
            $CloseButton.BorderThickness = New-Object System.Windows.Thickness(0)
        }

        # Stash the tab id on the button's Tag so the Click handler can stay a PLAIN scriptblock:
        # a .GetNewClosure() block would capture $TabSession.Id but runs in a detached dynamic
        # module that cannot resolve this module's private functions (Close-TabSession/
        # Write-LogOutput), throwing CommandNotFoundException. The handler recovers the id from its
        # sender's Tag instead (WPF passes the sender as the first positional argument).
        $CloseButton.Tag = $TabSession.Id
        $CloseButton.Add_Click({
                param($ClickSender)
                try {
                    $_ | Show-EventInfo
                    Close-TabSession -TabId $ClickSender.Tag
                }
                catch {
                    $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            })

        [void]$Grid.Children.Add($TitleText)
        [void]$Grid.Children.Add($CloseButton)

        return $Grid
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
