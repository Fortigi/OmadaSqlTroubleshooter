function Get-TreeViewItemLevel {
    param (
        [System.Windows.Controls.TreeViewItem]$TreeViewItem
    )
    try {
        $Level = 0
        $Parent = $TreeViewItem.Parent

        while ($null -eq $Parent) {
            if ($Parent -is [System.Windows.Controls.TreeViewItem]) {
                $Level++
            }
            $Parent = $Parent.Parent
        }

        return $Level
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}

