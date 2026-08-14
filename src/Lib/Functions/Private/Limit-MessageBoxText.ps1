function Limit-MessageBoxText {
    param([string]$Text)

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        $ScreenWidth = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
        $ScreenHeight = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height

        $MaxWidth = [math]::Floor($ScreenWidth * 0.8)
        $MaxCharsPerLine = [math]::Floor($MaxWidth / 8)

        $MaxLines = [math]::Floor(($ScreenHeight - 50) / 20)

        $Lines = $Text -split "`r`n|`n"
        $TruncatedLines = @()
        $LineCount = 0

        foreach ($Line in $Lines) {
            if ($LineCount -ge $MaxLines) {
                $TruncatedLines += "... (message truncated to fit screen)"
                break
            }

            if ($Line.Length -gt $MaxCharsPerLine) {
                $WrappedLine = $Line.Substring(0, [math]::Min($Line.Length, $MaxCharsPerLine - 3)) + "..."
                $TruncatedLines += $WrappedLine
            }
            else {
                $TruncatedLines += $Line
            }
            $LineCount++
        }

        return ($TruncatedLines -join "`r`n")
    }
    catch {
        if ($Text.Length -gt 1000) {
            return $Text.Substring(0, 997) + "..."
        }
        return $Text
    }
}
