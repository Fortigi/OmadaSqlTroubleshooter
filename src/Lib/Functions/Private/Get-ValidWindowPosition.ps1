function Get-ValidWindowPosition {
    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Form,
        [parameter(Mandatory = $true)]
        [string]$Setting
    )
    try {
        $ActionId = [guid]::NewGuid().ToString()
        if ($Setting -in "Left", "Top") {
            "{0} setting {1}: {2} (Id:{3})" -f $Form.Name, $Setting, $Form.$Setting, $ActionId | Write-LogOutput -LogType VERBOSE2
            if ($Setting -eq "Left") {
                $PrimaryScreenSetting = [system.windows.systemparameters]::PrimaryScreenWidth
                "PrimaryScreenSetting PrimaryScreenWidth {0}: {1} (Id:{2})" -f $Setting, $PrimaryScreenSetting, $ActionId | Write-LogOutput -LogType VERBOSE2
            }
            elseif ($Setting -eq "Top") {
                $PrimaryScreenSetting = [system.windows.systemparameters]::PrimaryScreenHeight
                "PrimaryScreenSetting PrimaryScreenHeight {0}: {1} (Id:{2})" -f $Setting, $PrimaryScreenSetting, $ActionId | Write-LogOutput -LogType VERBOSE2
            }

            if ($Form.$Setting -gt $PrimaryScreenSetting -or $Form.$Setting -lt 0) {
                $Form.$Setting = ($PrimaryScreenSetting - $Form.$Setting) / 2
                "{0} position from screen height '{1}x{2}'. Setting: '{3}' (Id:{4})" -f $Form.Name, $Form.Left, $Form.Top, $Setting, $ActionId | Write-LogOutput -LogType VERBOSE2
                return [Int]::Abs($Form.$Setting)
            }
            else {
                "{0} setting '{1}' (Id:{2})" -f $Form.Name, $Form.$Setting, $ActionId | Write-LogOutput -LogType VERBOSE2
                return [Int]::Abs($Form.$Setting)
            }
        }
        else {
            "{0} setting '{1}' is not valid. (Id:{2})" -f $Form.Name, $Form.$Setting, $ActionId | Write-LogOutput -LogType VERBOSE2
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
