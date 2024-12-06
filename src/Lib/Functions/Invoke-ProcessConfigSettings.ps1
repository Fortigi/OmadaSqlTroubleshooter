function Invoke-ProcessConfigSettings {

    PARAM(
        [parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        $Value,
        [parameter(Mandatory = $false)]
        [string]$Property,
        [switch]$Reset
    )

    try {
        if ($Reset) {
            "Reset configuration!" | Write-LogOutput -LogType DEBUG
            if (Test-Path $Script:ConfigFilePath -PathType Leaf) {
                Get-Item $Script:ConfigFilePath | Remove-Item -Force
            }
            $Script:AppConfig = $Null
        }

        $ConfigProperties = @("BaseUrl", "SqlQueryDoId", "SelectedSqlQueryDoId", "LastOutputFolder", "LastExtension", "LastAuthentication", "UserName", "LogLevel", "MyQueriesOnly", "IdentityUserName", "CurrentDataConnection", "CurrentDataConnectionId", "CurrentDataConnectionName", "LogWindowFormOpen", "SqlSchemaWindowFormOpen", "MainWindowPosition", "LogWindowPosition", "SqlSchemaWindowPosition", "MainWindowSize", "LogWindowSize", "SqlSchemaWindowSize", "ConfigMultiValueSeparator","LogWindowWordWrap","CheckboxConsoleLog")
        if ($Null -ne $Script:AppConfig) {
            $Config = $Script:AppConfig | ConvertTo-Json | ConvertFrom-Json

            $Config|Get-Member -MemberType NoteProperty | ForEach-Object {
                if ($ConfigProperties -notcontains $_.Name) {
                    "Remove obsolete property {0} from config object!" -f $_.Name | Write-LogOutput -LogType VERBOSE
                    $Config.PSObject.Properties.Remove($_.Name)
                }
            }

            $CurrentPoperties = $Config | Get-Member -MemberType NoteProperty
            $ConfigProperties | ForEach-Object {
                if ($_ -notin $CurrentPoperties.Name) {
                    "Add property {0} to config object!" -f $_ | Write-LogOutput -LogType VERBOSE
                    $Value = $Null
                    if ($_ -eq "LogLevel") {
                        $Value = "INFO"
                    }
                    if ($_ -eq "LastAuthentication") {
                        $Value = "Browser"
                    }
                    $Config | Add-Member -MemberType NoteProperty -Name $_ -Value $Value
                }
            }
            "Update config object!" | Write-LogOutput -LogType VERBOSE
        }
        else {
            if (Test-Path $Script:ConfigFilePath -PathType Leaf) {
                "Read config settings {0}!" -f $Script:ConfigFilePath | Write-LogOutput -LogType VERBOSE
                $Config = Get-Content $Script:ConfigFilePath | ConvertFrom-Json
                $CurrentPoperties = $Config | Get-Member -MemberType NoteProperty
                $ConfigProperties | ForEach-Object {
                    if ($_ -notin $CurrentPoperties.Name) {
                        "Add property {0} to config object!" -f $_ | Write-LogOutput -LogType VERBOSE
                        $Config | Add-Member -MemberType NoteProperty -Name $_ -Value $Null
                    }
                }
            }
            else {
                "Create new config object!" | Write-LogOutput -LogType DEBUG
                $Config = [pscustomobject]@{}
                $ConfigProperties | ForEach-Object {
                    "Add property {0} to config object!" -f $_ | Write-LogOutput -LogType VERBOSE
                    $Config | Add-Member -MemberType NoteProperty -Name $_ -Value $Null
                }
            }
        }

        if (![string]::IsNullOrWhiteSpace($Property)) {
            "Set value for property {0} in config object!" -f $Property | Write-LogOutput -LogType VERBOSE
            $Config.$Property = $Value
        }

        "Store config object to {0}. Contents`r`n{1}`r`n" -f $Script:ConfigFilePath, ($Config | ConvertTo-Json) | Write-LogOutput -LogType VERBOSE
        $Success = $false
        do {
            try {
                if (!$Success) {
                    $Config | ConvertTo-Json | Set-Content $Script:ConfigFilePath -Force
                    $Success = $true
                }
            }
            catch {
                if (!$Success) {
                    $ErrorObject = $_
                    "Error writing to file. Retry in 1 second" | Write-LogOutput -LogType WARNING -SkipDialog
                    Start-Sleep -Seconds 1
                }
            }
        }
        until($Count -ge 10 -or $Success)

        if (!$Success) {
            $ErrorObject.Exception.Message | Write-LogOutput -LogType ERROR -SkipDialog
        }

        $Script:AppConfig = $Config

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}

