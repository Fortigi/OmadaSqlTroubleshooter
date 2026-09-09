function Format-OmadaHistoryDate {
    <#
    .SYNOPSIS
        Renders a history change date for display, tolerating one that could not be read.

    .DESCRIPTION
        ConvertTo-OmadaHistoryDate returns $null when the server sent a change date that could not
        be parsed under either the invariant or the current culture (issue #95). The point of that
        was to cost the user one cell rather than the whole history list - so every place that
        DISPLAYS a change date has to survive the null as well, or the failure simply moves from
        the fetch to the first click. Calling .ToString() on it throws
        "You cannot call a method on a null-valued expression".

        The placeholder matches TargetNullValue on the grid column in SqlHistoryForm.xaml, so the
        row reads the same in the grid, in the detail pane and in an export.

    .PARAMETER Value
        The change date to render. May be $null.

    .EXAMPLE
        Format-OmadaHistoryDate -Value $Item.ChangeDate
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Position = 0)]
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return "(unknown)"
    }

    return ([DateTime]$Value).ToString("yyyy-MM-dd HH:mm:ss")
}
