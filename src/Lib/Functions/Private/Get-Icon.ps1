function Get-Icon {
    [CmdLetBinding()]
    param(
        [ValidateSet("Wpf", "WinForms", "Base64")]
        [string]$Type = "WinForms"
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        $ImagePath = (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\icons\AppIcon.ico")
        # Base64 encoded icon (Create via $Base64Icon = [Convert]::ToBase64String([IO.File]::ReadAllBytes("Icon file path")))
        $IconBytes = [IO.File]::ReadAllBytes($ImagePath)
        $Base64Icon = [System.Convert]::ToBase64String($IconBytes)

        $MemoryStream = New-Object System.IO.MemoryStream(, $IconBytes)

        switch ($Type) {
            "Wpf" {
                $Icon = New-Object System.Windows.Media.Imaging.BitmapImage
                $Icon.BeginInit()
                $Icon.StreamSource = $MemoryStream
                $Icon.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $Icon.EndInit()
                $Icon.Freeze()  # Freeze to make it thread-safe

                return $Icon
            }
            "WinForms" {
                return [System.Drawing.Icon]::new($MemoryStream)
            }
            default {
                return $Base64Icon
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
