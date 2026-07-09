function Initialize-OmadaSqlTroubleShooter {
    [CmdLetBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'WebView2AlreadyLoaded', Justification = 'The variable is used, but script analyzer does not recognize it')]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
        "Initializing application..." | Write-LogOutput -LogType DEBUG
        Push-Location $Script:RunTimeConfig.ModuleFolder

        $Script:RunTimeConfig.Logging.AppLogObject.Add("Application log initialized`r`n")
        $Script:RunTimeConfig.ConfigFile.Name = $($Script:RunTimeConfig.ScriptName -replace ".ps1", ""), ".json" -join ""
        if (Test-Path $Script:RunTimeConfig.AppDataFolder -PathType Container) {
            New-Item (Join-Path $Script:RunTimeConfig.AppDataFolder -ChildPath "config") -ItemType Directory -Force | Out-Null
            $Script:RunTimeConfig.ConfigFile.Path = (Join-Path $($Script:RunTimeConfig.AppDataFolder) -ChildPath "config\$($Script:RunTimeConfig.ConfigFile.Name)")
        }
        else {
            $Script:RunTimeConfig.ConfigFile.Path = Join-Path $($Script:RunTimeConfig.ModuleFolder) -ChildPath $($Script:RunTimeConfig.ConfigFile.Name)
        }


        try {
            Get-Variable | Where-Object { $_.Name -eq "Task" } | Remove-Variable -Force -ErrorAction SilentlyContinue
        }
        catch { }

        "Load module OmadaWeb.PS" | Write-LogOutput -LogType DEBUG
        Import-Module OmadaWeb.PS
        "Load Assemblies" | Write-LogOutput -LogType DEBUG

        ("System.Windows.Forms", "System.Drawing", "PresentationFramework", "WindowsBase", "PresentationCore", "PresentationFramework") | ForEach-Object {
            "Load assembly: '{0}'" -f $_ | Write-LogOutput -LogType DEBUG
            try {
                Add-Type -AssemblyName $_
            }
            catch {
                if ($_.Exception.Message -like '*Assembly with same name is already loaded*') {}
                else { throw $_.Exception.Message }
            }
        }
        Add-ReflectionAssembly -Object $Script:WebView2CorePath
        Add-ReflectionAssembly -Object $Script:WebView2WinFormsPath
        Add-ReflectionAssembly -Object $Script:WebView2WpfPath

        # Per-tab state ($RunTimeData/$WebView/$AppConfig/$ConnectionStatus/$Task/$MainForm.Elements)
        # now lives on each entry in $Script:Tabs and is repointed onto these same global names by
        # Set-ActiveTabContext, one tab at a time - see New-TabSession.ps1 for the per-tab shape
        # that used to be built here as a single, global instance.
        $Script:AppConfig = $null
        $Script:AppGlobalConfig = $null
        $Script:Tabs = [System.Collections.Generic.List[PSCustomObject]]::new()
        $Script:ActiveTabId = $null
        $Script:InteractiveLoginInProgress = $false
        $Script:SharedWebViewEnvironment = $null

        [Windows.Forms.Application]::EnableVisualStyles()

    }
    catch {
        throw $_
    }
}
