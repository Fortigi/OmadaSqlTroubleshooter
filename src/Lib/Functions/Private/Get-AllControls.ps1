function Get-AllControls {
    [CmdLetBinding()]
    param()
    param (
        [System.Windows.DependencyObject]$Parent
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
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
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }

}
