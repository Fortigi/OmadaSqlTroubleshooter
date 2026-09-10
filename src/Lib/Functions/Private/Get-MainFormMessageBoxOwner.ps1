function Get-MainFormMessageBoxOwner {
    <#
    .SYNOPSIS
    An IWin32Window for the main form, so a WinForms message box can be owned by it.

    .DESCRIPTION
    This application is WPF but raises its message boxes through System.Windows.Forms.MessageBox,
    which takes an IWin32Window rather than a WPF Window. Without one the dialog is a top-level window
    with no relationship to the application, and Windows will happily order it behind the main form -
    which is exactly what happened: an error about a failed query appeared behind the application, and
    because the dialog was modal the application underneath looked hung.

    WindowInteropHelper gets the main window's HWND; NativeWindow wraps it in the interface the
    message box wants. The caller must call ReleaseHandle() when the dialog closes - a NativeWindow
    that keeps a handle it does not own will complain when it is finalized.

    .OUTPUTS
    A System.Windows.Forms.NativeWindow assigned to the main window's handle, or $null when there is
    no usable window - during startup and shutdown, mainly - in which case the caller should fall back
    to the ownerless overload rather than not showing the dialog at all.
    #>
    [CmdLetBinding()]
    param()

    try {
        if ($null -eq $Script:MainForm -or $null -eq $Script:MainForm.Definition) {
            return $null
        }

        $Private:Handle = (New-Object System.Windows.Interop.WindowInteropHelper($Script:MainForm.Definition)).Handle
        if ($Private:Handle -eq [System.IntPtr]::Zero) {
            # The window exists as an object but has not been shown yet, so it has no HWND to own
            # anything.
            return $null
        }

        $Private:Owner = New-Object System.Windows.Forms.NativeWindow
        $Private:Owner.AssignHandle($Private:Handle)
        return $Private:Owner
    }
    catch {
        # An owner is an improvement, not a requirement. Failing to build one must never cost the
        # user the message itself.
        return $null
    }
}
