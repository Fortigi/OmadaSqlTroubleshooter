function Set-ShowLogButtonEnabled {
    <#
    .SYNOPSIS
    Enables or disables the "Show log" button on every open tab.

    .DESCRIPTION
    ButtonShowLog lives on each tab's content (MainFormTabContent.xaml), so $Script:MainForm.Elements
    only ever exposes the active tab's copy - and none at all before the first tab is created or after
    the last one is closed. The Log window's Loaded/Closed handlers used to poke
    $Script:MainForm.Elements.ButtonShowLog.IsEnabled directly, which threw "The property 'IsEnabled'
    cannot be found on this object" when the Log window opened before the first tab existed. Updating
    every tab's button here (guarding tabs whose button is missing) keeps the control consistent
    across tabs and never dereferences a null element.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        foreach ($Tab in $Script:Tabs) {
            $Button = $Tab.Elements.ButtonShowLog
            if ($null -ne $Button) {
                $Button.IsEnabled = $Enabled
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
