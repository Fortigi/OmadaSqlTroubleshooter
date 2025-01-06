function Invoke-LogWindowScrollToEnd {

    try {

        #TODO: Implement disable scroll when not at the end

        #         for ($i = 0; $i -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Element); $i++) {
        #             $Child = [System.Windows.Media.VisualTreeHelper]::GetChild($Element, $i)
        #             if ($Child -is [System.Windows.Controls.ScrollViewer]) {
        #                 return $Child
        #             } else {
        #                 $ScrollViewer = Get-ScrollViewer -Element $Child
        #                 if ($ScrollViewer) {
        #                     return $ScrollViewer
        #                 }
        #             }
        #         }


        #     $ScrollViewer = [System.Windows.Controls.Primitives.ScrollViewer]::GetScrollViewer($Script:TextBoxLog.ScrollToEnd())

        #     $ScrollViewer.ScrollChanged += {
        #         $VerticalOffset = $ScrollViewer.VerticalOffset
        #         $ExtentHeight = $ScrollViewer.ExtentHeight
        #         $ViewportHeight = $ScrollViewer.ViewportHeight

        #         if ($VerticalOffset -eq ($ExtentHeight - $ViewportHeight)) {
        return $true
        #         }
        #         else {
        #             return $false
        #         }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
