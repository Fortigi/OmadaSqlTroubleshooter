function Get-WindowAllowedMeasurement {

    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Form,
        [parameter(Mandatory = $true)]
        [string]$Setting
    )

    try {
        if ($Setting -in "Width", "Height") {

            if ($Form.$Setting -lt $Form.$("Min{0}" -f $Setting) -and $Form.$Setting -gt 0) {
                return [int32]$Form.$("Min{0}" -f $Setting)
            }
            else {
                return [int32]$Form.$Setting
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
