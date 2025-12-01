function Open-SplashScreenForm {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
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
        $SplashLabel.AutoSize = $true
        $SplashLabel.Location = New-Object System.Drawing.Point(55, 180)
        $SplashScreenForm.Controls.Add($SplashLabel)
        return $SplashScreenForm

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
