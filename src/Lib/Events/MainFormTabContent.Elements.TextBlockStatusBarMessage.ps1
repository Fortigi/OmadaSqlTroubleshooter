# Issue #119. The status bar message's tooltip is bound to its own Text in MainFormTabContent.xaml;
# this decides, every time it is about to open, whether the message is trimmed enough to need it.
#
# Show-EventInfo is left out on purpose: this fires on every hover over the bar, and a log line per
# hover would bury the events worth reading.
$Script:MainForm.Elements.TextBlockStatusBarMessage.Add_ToolTipOpening({
        param(
            $EventSender,
            $EventArguments
        )
        try {
            # The sender, not $Script:MainForm.Elements: that bag follows the active tab, and this
            # handler is wired once per tab when the tab is created.
            Confirm-TabStatusMessageToolTipOpening -StatusBlock $EventSender -EventArguments $EventArguments
        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType DEBUG
        }
    })
