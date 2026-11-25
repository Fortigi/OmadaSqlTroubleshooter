# The shortcuts in Get-KeyboardShortcut that run a menu command (Ctrl+N, Ctrl+Shift+N, Ctrl+Shift+E).
# A file and a handler of their own: the window's main key handler (MainForm.Definition.ps1) is over
# the complexity ceiling and on the baseline, which only ratchets down.
$Script:MainForm.Definition.Add_PreviewKeyDown({
        try {
            Invoke-KeyboardShortcut -KeyEventArgs $_
        }
        catch {
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
