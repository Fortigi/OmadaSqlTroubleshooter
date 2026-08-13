function Get-TreeViewItemLevel {
    [CmdLetBinding()]
    param (
        [System.Windows.Controls.TreeViewItem]$TreeViewItem
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
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
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}

