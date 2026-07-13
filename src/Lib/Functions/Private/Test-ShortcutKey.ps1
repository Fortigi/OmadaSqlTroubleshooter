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

    Takes the key and active modifiers as their [System.Windows.Input.Key] / [ModifierKeys] names
    (i.e. what .ToString() yields, such as "S", "LeftCtrl", "F5", "Control, Shift"). Working with
    names rather than the WPF enum types keeps this testable without loading PresentationCore.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$KeyName,
        [string]$ModifierNames = ""
    )

    # The Ctrl/Alt/Windows modifier keys themselves are never secret input and indicate shortcut
    # usage, so they are always loggable. Shift is deliberately excluded: logging a bare Shift press
    # would leak the capitalisation pattern of whatever is being typed.
    $ModifierKeyNames = @("LeftCtrl", "RightCtrl", "LeftAlt", "RightAlt", "LWin", "RWin")
    if ($KeyName -in $ModifierKeyNames) {
        return $true
    }

    if ($KeyName -match "^F([1-9]|1[0-9]|2[0-4])$") {
        return $true
    }

    # Any other key is only a shortcut when chorded with Ctrl, Alt or Windows. Shift alone does not
    # qualify (it is just capitalisation of ordinary typing). ModifierNames is the [ModifierKeys]
    # name string, e.g. "None", "Control", "Control, Shift".
    if ($ModifierNames -match "Control|Alt|Windows") {
        return $true
    }

    return $false
}
