function Test-ShortcutKey {
    <#
    .SYNOPSIS
    Returns whether a key event is part of a keyboard shortcut (and therefore safe and useful to
    log), as opposed to ordinary typing.

    .DESCRIPTION
    Security: key events are logged for shortcut tracing, but logging every keystroke would let a
    secret typed into a field (e.g. a password) be reconstructed from the log. A key counts as a
    shortcut only when:
      1. It is a Ctrl/Alt/Windows modifier key itself (safe to record - shows shortcut usage), or
      2. It is a function key (F1-F24, e.g. F5 = execute), or
      3. It is chorded with Ctrl, Alt or the Windows key.
    Bare character/navigation keys - and Shift-only combinations, which are just capitalisation -
    are NOT shortcuts, so this returns $false and keeps them out of the log.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Input.Key]$Key,
        [System.Windows.Input.ModifierKeys]$Modifiers = [System.Windows.Input.ModifierKeys]::None
    )

    # The Ctrl/Alt/Windows modifier keys themselves are never secret input and indicate shortcut
    # usage, so they are always loggable. Shift is deliberately excluded: logging a bare Shift press
    # would leak the capitalisation pattern of whatever is being typed.
    $ModifierKeyList = @(
        [System.Windows.Input.Key]::LeftCtrl
        [System.Windows.Input.Key]::RightCtrl
        [System.Windows.Input.Key]::LeftAlt
        [System.Windows.Input.Key]::RightAlt
        [System.Windows.Input.Key]::LWin
        [System.Windows.Input.Key]::RWin
    )
    if ($Key -in $ModifierKeyList) {
        return $true
    }

    if ($Key -ge [System.Windows.Input.Key]::F1 -and $Key -le [System.Windows.Input.Key]::F24) {
        return $true
    }

    # Any other key is only a shortcut when chorded with Ctrl, Alt or Windows. Shift alone does not
    # qualify (it is just capitalisation of ordinary typing).
    $ShortcutModifiers = [System.Windows.Input.ModifierKeys]::Control -bor [System.Windows.Input.ModifierKeys]::Alt -bor [System.Windows.Input.ModifierKeys]::Windows
    if (($Modifiers -band $ShortcutModifiers) -ne [System.Windows.Input.ModifierKeys]::None) {
        return $true
    }

    return $false
}
