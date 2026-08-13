function Open-SplashScreenForm {
    [CmdLetBinding()]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        "Loading Splash Screen" | Write-LogOutput -LogType DEBUG

        $Script:SplashScreenForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\SplashScreenForm.xaml")
        Import-EventObjects -ClassName "SplashScreenForm"

        try {
            $Script:SplashScreenForm.Elements.LogoImage.Source = Get-Icon -Type Wpf
        }
        catch {
            "Failed to load application icon for splash screen: {0}" -f $_.Exception.Message | Write-LogOutput -LogType WARNING
        }

        $Script:SplashScreenForm.Elements.TextboxSplashVersion.Content = "Version {0}`nFortigi (C) 2024-{1}" -f $Script:RunTimeConfig.ApplicationVersion, (Get-Date).ToString("yyyy")

        "Show Splash Screen" | Write-LogOutput -LogType DEBUG
        [void]$Script:SplashScreenForm.Definition.Show()
        return $Script:SplashScreenForm.Definition
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
