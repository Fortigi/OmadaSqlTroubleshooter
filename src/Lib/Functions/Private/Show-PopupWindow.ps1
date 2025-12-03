function Show-PopupWindow {
    [CmdLetBinding()]
    param(
        $Message
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        if ($null -eq $Script:MainFormForm -or $null -eq $Script:MainFormForm.Definition -or !$Script:MainFormForm.Definition.IsVisible) {
            return
        }

        $PopupWindow = New-Object System.Windows.Window
        $PopupWindow.WindowStyle = [System.Windows.WindowStyle]::None
        $PopupWindow.ResizeMode = [System.Windows.ResizeMode]::NoResize
        $PopupWindow.Width = 200
        $PopupWindow.Height = 50
        $PopupWindow.Background = [System.Windows.Media.Brushes]::White
        $PopupWindow.AllowsTransparency = $true
        $PopupWindow.Opacity = 0.8
        $PopupWindow.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
        $PopupWindow.Owner = $Script:MainFormForm.Definition
        $PopupWindow.ShowInTaskbar = $false
        $PopupWindow.Focusable = $false
        $PopupWindow.IsTabStop = $false

        $PopupWindow.Add_Closed({
                Restore-MainFormFocus
            })

        $Grid = New-Object System.Windows.Controls.Grid
        $Grid.Margin = '0'

        $PopupWindowBorder = New-Object System.Windows.Controls.Border
        $PopupWindowBorder.Background = [System.Windows.Media.Brushes]::Purple
        $PopupWindowBorder.CornerRadius = '5'
        $PopupWindowBorder.Padding = '5'


        $PopupWindowInsideBorder = New-Object System.Windows.Controls.Border
        $PopupWindowInsideBorder.Background = [System.Windows.Media.Brushes]::LightGray
        $PopupWindowInsideBorder.CornerRadius = '5'
        $PopupWindowInsideBorder.Padding = '5'


        $PopupWindowLabel = New-Object System.Windows.Controls.Label
        $PopupWindowLabel.Content = $Message
        $PopupWindowLabel.FontFamily = "Segoe UI"
        $PopupWindowLabel.FontSize = 12

        $PopupWindowLabel.FontWeight = "Bold"
        $PopupWindowLabel.HorizontalContentAlignment = "Center"
        $PopupWindowLabel.VerticalContentAlignment = "Center"
        $PopupWindowLabel.Foreground = [System.Windows.Media.Brushes]::Black

        $PopupWindowInsideBorder.Child = $PopupWindowLabel
        $PopupWindowBorder.Child = $PopupWindowInsideBorder
        $Grid.Children.Add($PopupWindowBorder) | Out-Null
        $PopupWindow.Content = $Grid

        $PopupWindow.Show() | Out-Null
        return $PopupWindow
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
