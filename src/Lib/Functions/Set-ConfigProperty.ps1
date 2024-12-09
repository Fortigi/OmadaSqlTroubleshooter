function Set-ConfigProperty {
    if ($_.Name -notin $CurrentPoperties.Name) {
       # "Add property {0} to config object!" -f $_ | Write-LogOutput -LogType VERBOSE
        $Value = $Null

        if ($_.Type -eq "Bool") {
            $Value = $false
        }
        elseif ($_.Type -eq "Int") {
            $Value = -1
        }
        elseif ($_.Type -eq "String") {
            $Value = $null
        }
        elseif ($_.Type -eq "PSObject") {
            $Value = [pscustomobject]@{}
            $_.Attributes | ForEach-Object {
                if ($_.Type -eq "Bool") {
                    $Value | Add-Member -MemberType NoteProperty -Name $_.Name -Value $false
                }
                elseif ($_.Type -eq "Int") {
                    $Value | Add-Member -MemberType NoteProperty -Name $_.Name -Value -1
                }
                elseif ($_.Type -eq "String") {
                    $Value | Add-Member -MemberType NoteProperty -Name $_.Name -Value $null
                }
                if ($_.DefaultValue) {
                    $Value.$($_.Name) = $_.DefaultValue
                }
            }
        }
        if ($_.DefaultValue) {
            $Value = $_.DefaultValue
        }
        $Config | Add-Member -MemberType NoteProperty -Name $_.Name -Value $Value
    }
}
