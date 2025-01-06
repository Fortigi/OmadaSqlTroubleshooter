function Set-WindowPosition {
    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Form,
        [parameter(Mandatory = $true)]
        [string]$Setting
    )
    try {
        $Form.Left | Write-Host -ForegroundColor DarkYellow
        $Form.Top | Write-Host -ForegroundColor DarkYellow

        $Form.Left = [Int]::Abs($Setting.Split("x")[0])
        $Form.Top = [Int]::Abs($Setting.Split("x")[1])
        $Form.Left | Write-Host -ForegroundColor Yellow
        $Form.Top | Write-Host -ForegroundColor Yellow

        "{0} position setting {1}: {2}x{3}" -f $Form.Name, $Setting, $Form.Left, $Form.Top | Write-LogOutput -LogType VERBOSE2

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
