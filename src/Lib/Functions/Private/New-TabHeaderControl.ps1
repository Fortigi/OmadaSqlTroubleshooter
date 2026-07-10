function New-TabHeaderControl {
    <#
    .SYNOPSIS
    Builds a tab header: a display-name TextBlock plus a close ("x") button, matching this
    codebase's existing pattern of building/mutating WPF controls directly in code rather than
    via XAML data-binding.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        $Panel = New-Object System.Windows.Controls.StackPanel
        $Panel.Orientation = [System.Windows.Controls.Orientation]::Horizontal

        $TitleText = New-Object System.Windows.Controls.TextBlock
        $TitleText.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        $TitleText.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $CloseButton = New-Object System.Windows.Controls.Button
        $CloseButton.Content = "x"
        $CloseButton.Width = 18
        $CloseButton.Height = 18
        $CloseButton.Padding = New-Object System.Windows.Thickness(0)
        $CloseButton.ToolTip = "Close tab"
        $CloseButton.IsEnabled = $true
        # $this is not bound to the sender in these WPF event scriptblocks, so capture
        # $TabSession's Id directly via GetNewClosure() rather than round-tripping through
        # a Tag property lookup on an unavailable/unbound $this.
        $CloseButton.Add_Click({
                try {
                    $_ | Show-EventInfo
                    Close-TabSession -TabId $TabSession.Id
                }
                catch {
                    $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
                }
            }.GetNewClosure())

        [void]$Panel.Children.Add($TitleText)
        [void]$Panel.Children.Add($CloseButton)

        return $Panel
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
