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

        $Form.Left = [double]$Setting.Split("x")[0]
        $Form.Top = [double]$Setting.Split("x")[1]
        $Form.Left | Write-Host -ForegroundColor Yellow
        $Form.Top | Write-Host -ForegroundColor Yellow

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
