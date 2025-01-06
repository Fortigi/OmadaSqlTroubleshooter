function Get-AllControls {
    param (
        [System.Windows.DependencyObject]$Parent
    )

    try {

        $Controls = @()
        if ($Parent -is [System.Windows.Controls.Control]) {
            $Controls += $Parent
        }

        # Iterate through child controls
        for ($i = 0; $i -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent); $i++) {
            $Child = [System.Windows.Media.VisualTreeHelper]::GetChild($Parent, $i)
            $Controls += Get-AllControls -Parent $Child
        }

        return $Controls

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }

}
