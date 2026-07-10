function Set-ConfigProperty {
    [CmdLetBinding()]

    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'CurrentProperties', Justification = 'The CurrentProperties variable is used in a function called from here')]
    param(
        [parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        $Value,
        [parameter(Mandatory = $false)]
        [string]$Property,
        [string]$JoinString = " - ",
        [switch]$Reset
    )

    begin {
        try {
            $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
            $InputObject = @()

            if ($null -eq $Script:TabConfigProperties) {
                "Read tab config schema!" | Write-LogOutput -LogType DEBUG
                $Script:TabConfigProperties = Get-Content (Join-Path (Get-ModuleBaseFolder) -ChildPath "lib\schema\appConfigSchema.json") | ConvertFrom-Json
            }
            if ($null -eq $Script:GlobalConfigProperties) {
                "Read global config schema!" | Write-LogOutput -LogType DEBUG
                $Script:GlobalConfigProperties = Get-Content (Join-Path (Get-ModuleBaseFolder) -ChildPath "lib\schema\appGlobalConfigSchema.json") | ConvertFrom-Json
            }

            # A tab-scope property mutates the active tab's own in-memory $Script:AppConfig
            # (persisted in bulk, once, by Save-TabSessions - not written to disk per-call here
            # any more). A global-scope property mutates $Script:AppGlobalConfig and is written
            # straight through to the single JSON config file, exactly like every property used
            # to be handled before tabs existed. A parameterless call (the shutdown "flush" call
            # site) always targets Global, since tab data is no longer flushed to disk per-call.
            $Script:ConfigPropertyScope = "Global"
            if (![string]::IsNullOrWhiteSpace($Property)) {
                if ($Script:TabConfigProperties.Name -contains $Property) {
                    $Script:ConfigPropertyScope = "Tab"
                }
                elseif ($Script:GlobalConfigProperties.Name -contains $Property) {
                    $Script:ConfigPropertyScope = "Global"
                }
                else {
                    "Property '{0}' was not found in either the tab or global config schema!" -f $Property | Write-LogOutput -LogType WARNING
                }
            }

            if ($Script:ConfigPropertyScope -eq "Tab") {
                $Script:ConfigProperties = $Script:TabConfigProperties

                if ($Reset) {
                    "-Reset only applies to the global config file; ignoring for a tab-scope property." | Write-LogOutput -LogType WARNING
                }

                if ($null -ne $Script:AppConfig) {
                    $Config = $Script:AppConfig | ConvertTo-Json | ConvertFrom-Json

                    $Config | Get-Member -MemberType NoteProperty | ForEach-Object {
                        if ($Script:ConfigProperties.Name -notcontains $_.Name) {
                            "Remove obsolete property {0} from tab config object!" -f $_.Name | Write-LogOutput -LogType VERBOSE
                            $Config.PSObject.Properties.Remove($_.Name)
                        }
                    }

                    $CurrentProperties = $Config | Get-Member -MemberType NoteProperty
                    $Script:ConfigProperties | ForEach-Object {
                        Add-ConfigProperty -Property $_
                    }
                    "Update tab config object!" | Write-LogOutput -LogType VERBOSE
                }
                else {
                    "Create new tab config object!" | Write-LogOutput -LogType DEBUG
                    $Config = [PSCustomObject]@{}
                    $Script:ConfigProperties | ForEach-Object {
                        Add-ConfigProperty -Property $_
                    }
                }
            }
            else {
                $Script:ConfigProperties = $Script:GlobalConfigProperties

                if ($Reset) {
                    "Reset configuration!" | Write-LogOutput -LogType DEBUG
                    if (Test-Path ($Script:RunTimeConfig.ConfigFile.Path) -PathType Leaf) {
                        Get-Item ($Script:RunTimeConfig.ConfigFile.Path) | Remove-Item -Force
                    }
                    $Script:AppGlobalConfig = $null
                }

                if ($null -ne $Script:AppGlobalConfig) {
                    $Config = $Script:AppGlobalConfig | ConvertTo-Json | ConvertFrom-Json

                    $Config | Get-Member -MemberType NoteProperty | ForEach-Object {
                        if ($Script:ConfigProperties.Name -notcontains $_.Name) {
                            "Remove obsolete property {0} from config object!" -f $_.Name | Write-LogOutput -LogType VERBOSE
                            $Config.PSObject.Properties.Remove($_.Name)
                        }
                    }

                    $CurrentProperties = $Config | Get-Member -MemberType NoteProperty
                    $Script:ConfigProperties | ForEach-Object {
                        Add-ConfigProperty -Property $_
                    }
                    "Update config object!" | Write-LogOutput -LogType VERBOSE
                }
                else {
                    if (Test-Path ($Script:RunTimeConfig.ConfigFile.Path) -PathType Leaf) {
                        "Read config settings {0}!" -f ($Script:RunTimeConfig.ConfigFile.Path) | Write-LogOutput -LogType VERBOSE
                        try {
                            $Config = Get-Content ($Script:RunTimeConfig.ConfigFile.Path) | ConvertFrom-Json
                            $CurrentProperties = $Config | Get-Member -MemberType NoteProperty
                            $CurrentProperties | ForEach-Object {
                                Add-ConfigProperty -Property $_
                            }
                        }
                        catch {
                            $_.Exception.Message | Write-LogOutput -LogType WARNING
                            "Config file corrupt, create a new config object!" | Write-LogOutput -LogType INFO
                            $Config = [PSCustomObject]@{}
                            $Script:ConfigProperties | ForEach-Object {
                                Add-ConfigProperty -Property $_
                            }
                        }
                    }
                    else {
                        "Create new config object!" | Write-LogOutput -LogType DEBUG
                        $Config = [PSCustomObject]@{}
                        $Script:ConfigProperties | ForEach-Object {
                            Add-ConfigProperty -Property $_
                        }
                    }
                }
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
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
                    "SecureString" {
                        if (![string]::IsNullOrEmpty($Value)) {
                            $Config.$Property = $Value | ConvertTo-SecureString -Force -AsPlainText | ConvertFrom-SecureString
                        }
                        else {
                            $Config.$Property = $null
                        }
                    }
                    "PSObject" {
                        if ($InputObject.Count -eq 1) {
                            $InputString = $InputObject[0].ToString()
                            $LastIndex = $InputString.LastIndexOf($JoinString)

                            if ($LastIndex -le -1) {
                                $Config.$Property = [PSCustomObject]@{
                                    DoId        = $InputString
                                    DisplayName = $null
                                    FullName    = $null
                                }
                            }
                            else {
                                $Config.$Property = [PSCustomObject]@{
                                    DoId        = [int]$InputString.Substring($LastIndex + ($JoinString.Length - 1)).Trim()
                                    DisplayName = $InputString.Substring(0, $LastIndex).Trim()
                                    FullName    = $null
                                }
                            }
                        }
                        else {
                            $Config.$Property = [PSCustomObject]@{
                                DoId        = [int]$InputObject[0]
                                DisplayName = $InputObject[1]
                                FullName    = $null
                            }
                        }
                        $Config.$Property.FullName = $Config.$Property.DisplayName, $Config.$Property.DoId -join " - "
                    }
                }
            }

            if ($Script:ConfigPropertyScope -eq "Tab") {
                # Tab-scope config lives only in memory here; Save-TabSessions persists every
                # tab's config to the encrypted Clixml store once, at application shutdown.
                $Script:AppConfig = $Config

                # $Config was rebuilt via a ConvertTo/From-Json round-trip above, so it's a new
                # object, not the same reference $TabSession.AppConfig already holds. Without
                # updating that reference too, the next Set-ActiveTabContext call (any routine
                # tab switch, or an async completion restoring context) would read the tab's own
                # stale AppConfig and silently revert this change - and Save-TabSessions reads
                # straight from $Tab.AppConfig, so it would persist the stale value as well.
                $ActiveTab = Get-ActiveTabSession
                if ($null -ne $ActiveTab) {
                    $ActiveTab.AppConfig = $Config
                }
            }
            else {
                "Store config object to {0}. Contents`r`n{1}`r`n" -f ($Script:RunTimeConfig.ConfigFile.Path), ($Config | ConvertTo-Json) | Write-LogOutput -LogType VERBOSE2
                $Success = $false
                $Count = 0
                do {
                    $Count++
                    try {
                        if (!$Success) {
                            $Config | ConvertTo-Json | Set-Content ($Script:RunTimeConfig.ConfigFile.Path) -Force
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

                $Script:AppGlobalConfig = $Config
            }
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    }
}
