function Open-SplashScreenForm {
    try {

        "Loading Splash Screen" | Write-LogOutput -LogType DEBUG
        $SplashScreenForm = New-Object System.Windows.Forms.Form
        $SplashScreenForm.Text = "Loading..."
        $SplashScreenForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $SplashScreenForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $SplashScreenForm.Width = 300
        $SplashScreenForm.Height = 250
        $SplashScreenForm.BackColor = [System.Drawing.Color]::White

        $LogoPictureBox = New-Object System.Windows.Forms.PictureBox
        $LogoPictureBox.Image = Get-Icon -Type WinForms
        $LogoPictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $LogoPictureBox.Width = 150
        $LogoPictureBox.Height = 150
        $LogoPictureBox.Location = New-Object System.Drawing.Point(65, 20)
        $SplashScreenForm.Controls.Add($LogoPictureBox)

        $SplashLabel = New-Object System.Windows.Forms.Label
        $SplashLabel.Text = "Initializing application..."
        $SplashLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
        $SplashLabel.AutoSize = $True
        $SplashLabel.Location = New-Object System.Drawing.Point(55, 180)
        $SplashScreenForm.Controls.Add($SplashLabel)
        return $SplashScreenForm

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
