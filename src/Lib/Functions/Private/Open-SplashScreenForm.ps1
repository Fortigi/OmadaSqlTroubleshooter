function Open-SplashScreenForm {
    [CmdLetBinding()]
    param()
    try {
        Wait-Debugger
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))

        "Loading Splash Screen" | Write-LogOutput -LogType DEBUG

        # Initialize the WPF splash screen form using the same pattern as other forms
        $Script:SplashScreenForm = Initialize-FormObject -FormPath (Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath "lib\ui\SplashScreenForm.xaml")

        # Set the application icon
        try {
            $Script:SplashScreenForm.Elements.LogoImage.Source = Get-Icon -Type Wpf
        }
        catch {
            "Failed to load application icon for splash screen: {0}" -f $_.Exception.Message | Write-LogOutput -LogType WARNING
        }

        # Set the version text
        Wait-Debugger
        $Script:SplashScreenForm.Elements.SplashVersion.Content = "Version {0}" -f $Script:RunTimeConfig.ApplicationVersion
        "Show Splash Screen" | Write-LogOutput -LogType DEBUG
        [void]$Script:SplashScreenForm.Definition.Show()
        return $Script:SplashScreenForm.Definition
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
