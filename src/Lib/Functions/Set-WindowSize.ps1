function Set-WindowSize {

    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Form,
        [parameter(Mandatory = $true)]
        [string]$Setting
    )
    try {
        $Form.Width = [double]$Setting.Split("x")[0]
        $Form.Height = [double]$Setting.Split("x")[1]

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
