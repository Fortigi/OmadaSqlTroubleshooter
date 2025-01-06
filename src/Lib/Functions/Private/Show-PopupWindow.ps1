function Show-PopupWindow {
    PARAM(
        $Message
    )
    try {

        if($null -eq $Script:MainWindowForm -or $null -eq $Script:MainWindowForm.Definition -or !$Script:MainWindowForm.Definition.IsVisible) {
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
        $PopupWindow.Owner = $Script:MainWindowForm.Definition
        $PopupWindow.ShowInTaskbar = $false

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
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
