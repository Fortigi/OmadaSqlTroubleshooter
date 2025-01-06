function Set-TextBoxWrapping {
    PARAM(
        $TextBox,
        [bool]$Wrap =$false
    )
    try {
        "Set TextBox wrapping to {0}" -f $Wrap | Write-LogOutput -LogType DEBUG
        if ($Wrap) {
            $TextBox.TextWrapping = "WrapWithOverflow"
        }
        else {
            $TextBox.TextWrapping = "NoWrap"
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
