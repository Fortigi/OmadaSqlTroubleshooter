function Show-ChoiceWindow {
    [CmdLetBinding(
    )]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LeftButtonReturnValue', Justification = 'The LeftButtonReturnValue variable is used in a function called from here')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'RightButtonReturnValue', Justification = 'The RightButtonReturnValue variable is used in a function called from here')]
    param(
        $Title,
        $Message,
        $LeftButtonText = "Yes",
        $RightButtonText = "No",
        $LeftButtonReturnValue = $true,
        $RightButtonReturnValue = $false
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        $PopupWindow = New-Object System.Windows.Window
        $PopupWindow.WindowStyle = [System.Windows.WindowStyle]::SingleBorderWindow
        $PopupWindow.ResizeMode = [System.Windows.ResizeMode]::NoResize
        $PopupWindow.SizeToContent = [System.Windows.SizeToContent]::WidthAndHeight
        $PopupWindow.MinWidth = 400
        $PopupWindow.Background = [System.Windows.Media.Brushes]::White
        $PopupWindow.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
        $PopupWindow.Title = $Title
        $PopupWindow.ShowInTaskbar = $true
        $PopupWindow.Icon = Get-Icon -Type Wpf

        $Grid = New-Object System.Windows.Controls.Grid
        $Grid.Margin = '10'

        # Define grid rows
        $row0 = New-Object System.Windows.Controls.RowDefinition
        $row1 = New-Object System.Windows.Controls.RowDefinition
        $Grid.RowDefinitions.Add($row0)
        $Grid.RowDefinitions.Add($row1)

        $PopupWindowBorder = New-Object System.Windows.Controls.Border

        $PopupWindowInsideBorder = New-Object System.Windows.Controls.Border

        $PopupWindowLabel = New-Object System.Windows.Controls.Label
        $WrappedText = New-Object System.Windows.Controls.TextBlock
        $WrappedText.Text = $Message
        $WrappedText.TextWrapping = "Wrap"
        $WrappedText.MaxWidth = 600
        $WrappedText.FontFamily = "Segoe UI"
        $WrappedText.FontSize = 12
        $PopupWindowLabel.Content = $WrappedText
        $PopupWindowLabel.HorizontalContentAlignment = "Left"
        $PopupWindowLabel.VerticalContentAlignment = "Center"
        $PopupWindowLabel.Margin = "0,0,0,10"
        $PopupWindowLabel.Foreground = [System.Windows.Media.Brushes]::Black
        $PopupWindowLabel.MaxWidth = 600

        $PopupWindowInsideBorder.Child = $PopupWindowLabel
        $PopupWindowBorder.Child = $PopupWindowInsideBorder
        $Grid.Children.Add($PopupWindowBorder) | Out-Null

        # Create the button panel
        $ButtonPanel = New-Object System.Windows.Controls.StackPanel
        $ButtonPanel.Orientation = "Horizontal"
        $ButtonPanel.HorizontalAlignment = "Center"
        $ButtonPanel.SetValue([System.Windows.Controls.Grid]::RowProperty, 1)

        $LeftButton = New-Object System.Windows.Controls.Button
        $LeftButton.Content = $LeftButtonText
        $LeftButton.Width = 80
        $LeftButton.Height = 25
        $LeftButton.Margin = "0,0,15,0"
        $LeftButton.Background = [System.Windows.Media.Brushes]::LightBlue

        $RightButton = New-Object System.Windows.Controls.Button
        $RightButton.Content = $RightButtonText
        $RightButton.Width = 80
        $RightButton.Height = 25
        $RightButton.Background = [System.Windows.Media.Brushes]::LightGray

        $ButtonPanel.Children.Add($LeftButton) | Out-Null
        $ButtonPanel.Children.Add($RightButton) | Out-Null

        $Grid.Children.Add($ButtonPanel) | Out-Null

        $script:DialogResult = $null

        $LeftButton.Add_Click({
                $script:DialogResult = $LeftButtonReturnValue
                $PopupWindow.Close()
            })

        $RightButton.Add_Click({
                $script:DialogResult = $RightButtonReturnValue
                $PopupWindow.Close()
            })

        $PopupWindow.Add_Loaded({
                $LeftButton.Focus() | Out-Null
                $PopupWindow.Focus() | Out-Null
            })

        $PopupWindow.Content = $Grid

        $PopupWindow.ShowDialog() | Out-Null
        return $script:DialogResult
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
