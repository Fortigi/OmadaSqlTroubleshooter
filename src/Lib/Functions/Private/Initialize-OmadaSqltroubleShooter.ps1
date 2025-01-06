function Initialize-OmadaSqlTroubleShooter {

    try {
        "Initializing application..." | Write-LogOutput -LogType DEBUG

        Push-Location $Script:RunTimeConfig.ModuleFolder

        $Script:RunTimeConfig.Logging.AppLogObject.Add("Application log initialized`r`n")
        $Script:RunTimeConfig.ConfigFile.Name = $Script:RunTimeConfig.ScriptName -replace ".ps1", ".json"
        If (Test-Path $Script:RunTimeConfig.AppDataFolder -PathType Container) {
            New-Item (Join-Path $Script:RunTimeConfig.AppDataFolder -ChildPath "config") -ItemType Directory -Force | Out-Null
            $Script:RunTimeConfig.ConfigFile.Path = (Join-Path $($Script:RunTimeConfig.AppDataFolder) -ChildPath "config\$($Script:RunTimeConfig.ConfigFile.Name)")
        }
        else {
            $Script:RunTimeConfig.ConfigFile.Path = Join-Path $($Script:RunTimeConfig.ModuleFolder) -ChildPath $($Script:RunTimeConfig.ConfigFile.Name)
        }


        try {
            Remove-Variable "Task" -ErrorAction SilentlyContinue
        }
        catch { $Error.Clear() }

        "Load module OmadaWeb.PS" | Write-LogOutput -LogType DEBUG
        Import-Module OmadaWeb.PS

        "Load Assemblies" | Write-LogOutput -LogType DEBUG
        #Set path to the bin folder to be sure that WebView2Loader.dll is found there.
        $Env:Path += ";$($Script:RunTimeConfig.ModuleFolder)\Bin"
        $Env:Path += ";$($Script:RunTimeConfig.ModuleFolder)\Bin\Webview2Dlls"
        $Env:Path += ";$($Script:RunTimeConfig.ModuleFolder)"

        ("System.Windows.Forms", "System.Drawing", "PresentationFramework", "WindowsBase", "PresentationCore", "PresentationFramework") | ForEach-Object {
            "Load assembly: '{0}'" -f $_ | Write-LogOutput -LogType DEBUG
            Add-Type -AssemblyName $_
        }

        "Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.Wpf.dll" | ForEach-Object {
            "Load assembly: '{0}'" -f $_ | Write-LogOutput -LogType DEBUG
            $WebViewDllPath = Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "Bin\WebView2Dlls\$_"
            if ((Test-Path $WebViewDllPath -PathType Leaf)) {
                [System.Reflection.Assembly]::LoadFrom($WebViewDllPath) | Out-Null
            }
            else {
                Throw ("The WebView2 Dll '{0}' is cannot be found at the '{1}' bin folder!" -f $_, $DllSource)
                Break
            }
        }
        $WebViewLoaderPath = Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "Bin\WebView2Dlls\WebView2Loader.dll"
        "Get 'WebView2Loader.Dll'" | Write-LogOutput -LogType DEBUG
        if (!(Test-Path $WebViewLoaderPath -PathType Leaf)) {
            Throw ("The WebView2Loader Dll '{0}' is cannot be found at the '{1}' bin folder!" -f "WebView2Loader.dll", $DllSource)
            Break
        }

        $Script:AppConfig = $null
        $Script:RunTimeData = [PSCustomObject]@{
            RestMethodParam                = @{
                Uri                = $Null
                Method             = "GET"
                AuthenticationType = $($Script:AppConfig.LastAuthentication)
            }
            QuerySaved                     = $false
            Password                       = $Null
            QueryText                      = $null
            SqlQueryObject                 = $null
            QueryResult                    = $null
            CurrentQueryText               = $null
            CurrentSqlQuery                = [PSCustomObject]@{
                DoId        = $null
                DisplayName = $null
                FullName    = $null
            }
            StopWatch                      = $null
            QueryListCache                 = @{
                QueryList   = $null
                LastRefresh = Get-Date
                TTL         = 300
            }
            DataobjdlgAspxAttributeMapping = [PSCustomObject]@{
                SqlQueryDoId      = "c-13"
                SqlQueryCreatedBy = "c-2"
                SqlQueryChangedBy = "c-4"
            }
        }
        $Script:WebView = @{
            Object                  = $null
            Environment             = $null
            EdgeWebview2RuntimePath = $null
            UserDataFolder          = $null
        }

        [Windows.Forms.Application]::EnableVisualStyles()

    }
    catch {
        Throw $_
    }
}
