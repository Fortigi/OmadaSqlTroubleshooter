function Get-ValidWindowMeasurement {
    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Form,
        [parameter(Mandatory = $true)]
        [string]$Setting
    )

    try {
        if ($Setting -in "Width", "Height") {

            $SettingString = "Min{0}" -f $Setting
            if ($Form.$Setting -lt $Form.$SettingString -and $Form.$Setting -gt 0) {
                return [Int]$Form.$SettingString
            }
            else {
                return [Int]$Form.$Setting
            }
        }

        # if ($Setting -eq "Top") {
        #     if($Form.$("{0}most" -f $Setting))
        #         return [Windows.Window.SCreens]
        # }

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }

}
