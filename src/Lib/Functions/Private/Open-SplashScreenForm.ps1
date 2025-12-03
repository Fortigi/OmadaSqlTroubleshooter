function Open-SplashScreenForm {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        "Loading Splash Screen" | Write-LogOutput -LogType DEBUG

        $Script:SplashScreenForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\SplashScreenForm.xaml")

        try {
            $Script:SplashScreenForm.Elements.LogoImage.Source = Get-Icon -Type Wpf
        }
        catch {
            "Failed to load application icon for splash screen: {0}" -f $_.Exception.Message | Write-LogOutput -LogType WARNING
        }

        $Script:SplashScreenForm.Elements.SplashVersion.Content = "Version {0}" -f $Script:RunTimeConfig.ApplicationVersion
        "Show Splash Screen" | Write-LogOutput -LogType DEBUG
        [void]$Script:SplashScreenForm.Definition.Show()
        return $Script:SplashScreenForm.Definition
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
