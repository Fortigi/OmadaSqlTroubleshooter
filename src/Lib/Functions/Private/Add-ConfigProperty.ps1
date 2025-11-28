function Add-ConfigProperty {
    [CmdLetBinding()]
    param(
        $Property
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement))
        if ($Property.Name -notin $CurrentProperties.Name) {
            # "Add property {0} to config object!" -f $Property | Write-LogOutput -LogType VERBOSE
            $Private:Value = $null

            if ($Property.Type -eq "Bool") {
                $Private:Value = $false
            }
            elseif ($Property.Type -eq "Int") {
                $Private:Value = -1
            }
            elseif ($Property.Type -eq "String") {
                $Private:Value = $null
            }
            elseif ($Property.Type -eq "SecureString") {
                $Private:Value = $null
            }
            elseif ($Property.Type -eq "PSObject") {
                $Private:Value = [PSCustomObject]@{}
                $Property.Attributes | ForEach-Object {
                    if ($Property.Type -eq "Bool") {
                        $Private:Value | Add-Member -MemberType NoteProperty -Name $Property.Name -Value $false
                    }
                    elseif ($Property.Type -eq "Int") {
                        $Private:Value | Add-Member -MemberType NoteProperty -Name $Property.Name -Value -1
                    }
                    elseif ($Property.Type -eq "String") {
                        $Private:Value | Add-Member -MemberType NoteProperty -Name $Property.Name -Value $null
                    }
                    elseif ($Property.Type -eq "SecureString") {
                        $Private:Value | Add-Member -MemberType NoteProperty -Name $Property.Name -Value $null
                    }
                    if ($Property.DefaultValue) {
                        $Private:Value.$($Property.Name) = $Property.DefaultValue
                    }
                }
            }
            if ($Property.DefaultValue) {
                $Private:Value = $Property.DefaultValue
            }
            $Config | Add-Member -MemberType NoteProperty -Name $Property.Name -Value $Private:Value
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
