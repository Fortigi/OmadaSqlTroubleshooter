function Invoke-ConfigSetting {

    PARAM(
        [parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        $Value,
        [parameter(Mandatory = $false)]
        [string]$Property,
        [string]$JoinString = " - ",
        [switch]$Reset
    )

    begin {
        try {
            $InputObject = @()
            if ($Reset) {
                "Reset configuration!" | Write-LogOutput -LogType DEBUG
                if (Test-Path $Script:ConfigFilePath -PathType Leaf) {
                    Get-Item $Script:ConfigFilePath | Remove-Item -Force
                }
                $Script:AppConfig = $Null
            }

            if ($null -eq $Script:ConfigProperties) {
                "Read schema!" | Write-LogOutput -LogType DEBUG
                $Script:ConfigProperties = Get-Content (Join-Path (Split-Path $PSScriptRoot) -ChildPath "schema\appConfigSchema.json") | ConvertFrom-Json
            }

            if ($Null -ne $Script:AppConfig) {
                $Config = $Script:AppConfig | ConvertTo-Json | ConvertFrom-Json

                $Config | Get-Member -MemberType NoteProperty | ForEach-Object {
                    if ($Script:ConfigProperties.Name -notcontains $_.Name) {
                        "Remove obsolete property {0} from config object!" -f $_.Name | Write-LogOutput -LogType VERBOSE
                        $Config.PSObject.Properties.Remove($_.Name)
                    }
                }

                $CurrentPoperties = $Config | Get-Member -MemberType NoteProperty
                $Script:ConfigProperties | ForEach-Object {
                    Set-ConfigProperty
                }
                "Update config object!" | Write-LogOutput -LogType VERBOSE
            }
            else {
                if (Test-Path $Script:ConfigFilePath -PathType Leaf) {
                    "Read config settings {0}!" -f $Script:ConfigFilePath | Write-LogOutput -LogType VERBOSE
                    $Config = Get-Content $Script:ConfigFilePath | ConvertFrom-Json
                    $CurrentPoperties = $Config | Get-Member -MemberType NoteProperty
                    $Script:ConfigProperties | ForEach-Object {
                        Set-ConfigProperty
                    }
                }
                else {
                    "Create new config object!" | Write-LogOutput -LogType DEBUG
                    $Config = [pscustomobject]@{}
                    $Script:ConfigProperties | ForEach-Object {
                        Set-ConfigProperty
                    }
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }
    }
    process {
        $InputObject += $Value
        $Value = $Value
    }
    end {
        try {
            if (![string]::IsNullOrWhiteSpace($Property)) {
                "Set value for property {0} in config object!" -f $Property | Write-LogOutput -LogType VERBOSE

                $PropertyDefinition = $Script:ConfigProperties | Where-Object { $_.Name -eq $Property }

                switch ($PropertyDefinition.Type) {
                    "String" {
                        $Config.$Property = $Value
                    }
                    "Int" {
                        $Config.$Property = [int]$Value
                    }
                    "Bool" {

                        $Config.$Property = [bool]$Value
                    }
                    "PSObject" {
                        if ($InputObject.Count -eq 1) {
                            $InputString = $InputObject[0]
                            $LastIndex = $InputString.LastIndexOf($JoinString)

                            $Config.$Property = [pscustomobject]@{
                                DoId        = [int]$InputString.Substring($LastIndex + ($JoinString.Length - 1)).Trim()
                                DisplayName = $InputString.Substring(0, $LastIndex).Trim()
                                FullName    = $null
                            }
                        }
                        else {
                            $Config.$Property = [pscustomobject]@{
                                DoId        = [int]$InputObject[0]
                                DisplayName = $InputObject[1]
                                FullName    = $null
                            }
                        }
                        $Config.$Property.FullName = $Config.$Property.DisplayName, $Config.$Property.DoId -join " - "
                    }
                }
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
}

