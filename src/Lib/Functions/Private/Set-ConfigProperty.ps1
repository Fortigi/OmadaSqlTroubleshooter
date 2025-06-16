function Set-ConfigProperty {
    [CmdLetBinding()]
    PARAM(
        $Property
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName), $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        if ($Property.Name -notin $CurrentProperties.Name) {
            # "Add property {0} to config object!" -f $Property | Write-LogOutput -LogType VERBOSE
            $Value = $Null

            if ($Property.Type -eq "Bool") {
                $Value = $false
            }
            elseif ($Property.Type -eq "Int") {
                $Value = -1
            }
            elseif ($Property.Type -eq "String") {
                $Value = $null
            }
            elseif ($Property.Type -eq "PSObject") {
                $Value = [pscustomobject]@{}
                $Property.Attributes | ForEach-Object {
                    if ($Property.Type -eq "Bool") {
                        $Value | Add-Member -MemberType NoteProperty -Name $Property.Name -Value $false
                    }
                    elseif ($Property.Type -eq "Int") {
                        $Value | Add-Member -MemberType NoteProperty -Name $Property.Name -Value -1
                    }
                    elseif ($Property.Type -eq "String") {
                        $Value | Add-Member -MemberType NoteProperty -Name $Property.Name -Value $null
                    }
                    if ($Property.DefaultValue) {
                        $Value.$($Property.Name) = $Property.DefaultValue
                    }
                }
            }
            if ($Property.DefaultValue) {
                $Value = $Property.DefaultValue
            }
            $Config | Add-Member -MemberType NoteProperty -Name $Property.Name -Value $Value
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
