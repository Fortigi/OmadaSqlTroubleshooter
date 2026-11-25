function Get-KeyboardShortcut {
    <#
    .SYNOPSIS
        Every keyboard shortcut of the application: what the Help window lists, and what
        Invoke-KeyboardShortcut runs.

    .DESCRIPTION
        One list, so the shortcuts that are shown are the ones that exist:

          Gesture  What is shown, and on the menu item (InputGestureText); a test holds the menu bar's
                   gestures to this list.
          Key /    The key and the modifiers (ModifierKeys names) Invoke-KeyboardShortcut matches,
          Modifier for the entries it runs.
          Tag      The menu bar command it runs (see Resolve-MainMenuItemState), so a shortcut does
                   exactly what its menu item does, with the same enabled check.
          Handler  Who handles the key:
                     Shortcut  Invoke-KeyboardShortcut, from this list.
                     Window    The main window's own key handler (MainForm.Definition.ps1), the
                               editor's (index.html) or the result grid's - shortcuts that predate
                               this list and carry their own conditions (execute a selection from the
                               editor, copy from the focused result). Listed for the Help window only.
          Menu     The menu the command is on ("" for none).
          Where    Where the shortcut works.

    .OUTPUTS
        [PSCustomObject[]]
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # Gesture, Key, Modifier, Tag, Handler, Menu, Where, Description
    $Private:List = @(
        ,@("F5", "", "", "Button:ButtonExecuteQuery", "Window", "Query", "Anywhere in the main window", "Execute the query, or the selected text in the editor")
        ,@("Ctrl+N", "N", "Control", "Button:ButtonNewQuery", "Shortcut", "File", "Anywhere in the main window", "New query (clears the editor)")
        ,@("Ctrl+S", "", "", "Button:ButtonSaveQuery", "Window", "File", "Anywhere in the main window", "Save the query")
        ,@("Ctrl+Shift+D", "", "", "Action:ResultsToGrid", "Window", "Query", "Anywhere in the main window", "Results to grid")
        ,@("Ctrl+Shift+T", "", "", "Action:ResultsToText", "Window", "Query", "Anywhere in the main window", "Results to text")
        ,@("Ctrl+Shift+E", "E", "Control, Shift", "Button:ButtonSaveOutputFile", "Shortcut", "Results", "Anywhere in the main window", "Export the results")
        ,@("Ctrl+Shift+N", "N", "Control, Shift", "Tab:New", "Shortcut", "Window", "Anywhere in the main window", "New tab")
        ,@("Ctrl+Shift+K", "", "", "Tab:Duplicate", "Window", "Window", "Anywhere in the main window", "Duplicate the tab")
        ,@("Ctrl+T", "", "", "Tab:DuplicateWithoutQuery", "Window", "Window", "Anywhere in the main window", "Duplicate the tab without its query")
        ,@("Ctrl+Tab", "", "", "Tab:Next", "Window", "Window", "Anywhere in the main window", "Next tab")
        ,@("Ctrl+Shift+Tab", "", "", "Tab:Previous", "Window", "Window", "Anywhere in the main window", "Previous tab")
        ,@("Ctrl+W", "", "", "Tab:Close", "Window", "Window", "Anywhere in the main window", "Close the tab (also Ctrl+F4)")
        ,@("Ctrl+C", "", "", "Result:Copy", "Window", "Results", "Result grid", "Copy the selected cells")
        ,@("Ctrl+Shift+C", "", "", "Result:CopyWithHeader", "Window", "Results", "Result grid", "Copy the selected cells with their headers")
        ,@("Ctrl+Shift+S", "", "", "Result:CopyAsSqlArray", "Window", "Results", "Result grid", "Copy the selected cells as a SQL array")
        ,@("Ctrl+Shift+P", "", "", "Result:CopyAsPowerShellArray", "Window", "Results", "Result grid", "Copy the selected cells as a PowerShell array")
        ,@("Ctrl+A", "", "", "Result:SelectAll", "Window", "Results", "Result grid", "Select all cells")
        ,@("Enter", "", "", "", "Window", "", "Connection fields", "Connect")
        ,@("Alt+F4", "", "", "App:Exit", "Window", "File", "Anywhere in the main window", "Exit")
    )

    foreach ($Private:Entry in $Private:List) {
        [PSCustomObject]@{
            Gesture     = $Private:Entry[0]
            Key         = $Private:Entry[1]
            Modifier    = $Private:Entry[2]
            Tag         = $Private:Entry[3]
            Handler     = $Private:Entry[4]
            Menu        = $Private:Entry[5]
            Where       = $Private:Entry[6]
            Description = $Private:Entry[7]
        }
    }
}

function Resolve-KeyboardShortcut {
    <#
    .SYNOPSIS
        The menu command a key press runs, for the shortcuts Invoke-KeyboardShortcut handles.

    .DESCRIPTION
        Takes the key and the modifiers as their [System.Windows.Input.Key] / [ModifierKeys] names
        (what .ToString() gives: "N", "Control, Shift"), so it is tested without WPF. The modifiers
        must match exactly: Ctrl+N is not Ctrl+Shift+N.

    .PARAMETER KeyName
        The key.

    .PARAMETER ModifierNames
        The modifiers held.

    .OUTPUTS
        [string] The menu Tag, or $null when the key is not one of them.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$KeyName,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$ModifierNames = ""
    )

    $Private:Held = ConvertTo-ModifierSet -ModifierNames $ModifierNames
    foreach ($Private:Shortcut in @(Get-KeyboardShortcut | Where-Object { $_.Handler -eq "Shortcut" -and $_.Key -eq $KeyName })) {
        if ((ConvertTo-ModifierSet -ModifierNames $Private:Shortcut.Modifier) -eq $Private:Held) {
            return $Private:Shortcut.Tag
        }
    }
    return $null
}

function ConvertTo-ModifierSet {
    <#
    .SYNOPSIS
        A ModifierKeys name ("Shift, Control") in a fixed order ("Control,Shift"), so two of them
        compare as text. "None" and empty are no modifiers.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$ModifierNames = ""
    )

    return (@($ModifierNames -split "\s*,\s*" | Where-Object { $_ -and $_ -ne "None" }) | Sort-Object) -join ","
}

function Invoke-KeyboardShortcut {
    <#
    .SYNOPSIS
        The main window's PreviewKeyDown for the shortcuts in Get-KeyboardShortcut: runs the menu
        command of a matching key and marks the key handled.

    .DESCRIPTION
        A key that is not one of them is left alone for the other handlers. A key that is runs its
        menu command through Invoke-MainMenuAction - so it does what the menu item does, and nothing
        when that is disabled - and is marked handled either way, so it does not also reach the editor
        or a text box.

        A repeat of a held key is ignored: holding Ctrl+Shift+N must not open a tab per repeat.

    .PARAMETER KeyEventArgs
        The KeyEventArgs.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $KeyEventArgs
    )

    if ($KeyEventArgs.Handled -or $KeyEventArgs.IsRepeat) {
        return
    }

    $Private:Tag = Resolve-KeyboardShortcut -KeyName ([string]$KeyEventArgs.Key) -ModifierNames ([string]$KeyEventArgs.KeyboardDevice.Modifiers)
    if ([string]::IsNullOrEmpty($Private:Tag)) {
        return
    }

    $KeyEventArgs.Handled = $true
    "Shortcut {0}: {1}" -f [string]$KeyEventArgs.Key, $Private:Tag | Write-LogOutput -LogType VERBOSE
    Invoke-MainMenuAction -Tag $Private:Tag
}
