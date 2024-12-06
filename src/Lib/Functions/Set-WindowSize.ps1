function Set-WindowSize {

    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Form,
        [parameter(Mandatory = $true)]
        [string]$Setting
    )
    try {
        $Form.Width = [int32]::Abs($Setting.Split("x")[0])
        $Form.Height = [int32]::Abs($Setting.Split("x")[1])

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
