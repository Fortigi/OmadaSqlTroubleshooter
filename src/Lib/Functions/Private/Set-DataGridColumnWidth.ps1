function Set-DataGridColumnWidth {
    <#
    .SYNOPSIS
        Gives every column of a grid a fixed width from its widest value, capped, so the columns do
        not change width while the grid is scrolled.

    .DESCRIPTION
        A DataGrid column sized Auto takes the width of the cells it has realised, and a virtualised
        grid realises only the rows on screen: scrolling brings a longer value into view and the
        column jumps wider. So the width is worked out once, from the rows themselves:

          - per column, the header and the -Candidates longest values (by length, longest line of a
            multi-line value) are measured in the grid's own font (Measure-DataGridText), and the widest
            plus the cell's padding is the width;
          - capped at -MaxWidth, so one very long value does not make a column the width of the screen;
          - never under -MinWidth;
          - set as a pixel width, which the user can still drag wider or narrower: the cap is only
            applied here, not set on the column.

        The longest values are found by a compiled helper (Initialize-DataGridColumnTextType), which
        reads every row in milliseconds. At most -MaxRows rows are read all the same, so a result of
        millions of rows cannot stall the grid; a wider value below that is cut off at the column's
        edge rather than widening it - which is what keeps the column still.

    .PARAMETER Grid
        The DataGrid.

    .PARAMETER Item
        The rows to measure. Defaults to the grid's ItemsSource; the query manager passes its whole
        list so a filter that shows fewer rows does not need narrower columns.

    .PARAMETER MaxWidth
        The widest a column is made.

    .PARAMETER MinWidth
        The narrowest a column is made.

    .PARAMETER MaxRows
        How many rows are read.

    .PARAMETER Candidates
        How many of a column's longest values are measured.

    .PARAMETER Measure
        Measures a text: { param($Grid, $Text) <width> }. Defaults to Measure-DataGridText (WPF).

    .OUTPUTS
        [double[]] The widths set, in column order.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        $Grid,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Item,

        [double]$MaxWidth = 400,

        [double]$MinWidth = 40,

        [int]$MaxRows = 200000,

        [int]$Candidates = 3,

        [scriptblock]$Measure = { param($MeasureGrid, $Text) Measure-DataGridText -Grid $MeasureGrid -Text $Text }
    )

    $Private:Rows = if ($PSBoundParameters.ContainsKey("Item")) { @($Item) } else { @($Grid.ItemsSource) }
    $Private:Rows = @($Private:Rows | Where-Object { $null -ne $_ } | Select-Object -First $MaxRows)

    # Room for the cell's padding and border, and for the sort arrow in the header.
    $Private:CellPadding = 14
    $Private:HeaderPadding = 26

    foreach ($Private:Column in @($Grid.Columns)) {
        $Private:Key = Get-DataGridColumnKey -Column $Private:Column
        $Private:Texts = @(Get-DataGridColumnTextCandidate -Row $Private:Rows -Key $Private:Key -Count $Candidates)

        $Private:Widest = [double](& $Measure $Grid ([string]$Private:Column.Header)) + $Private:HeaderPadding
        foreach ($Private:Text in $Private:Texts) {
            $Private:Widest = [Math]::Max($Private:Widest, [double](& $Measure $Grid $Private:Text) + $Private:CellPadding)
        }

        $Private:Width = [Math]::Ceiling([Math]::Max($MinWidth, [Math]::Min($MaxWidth, $Private:Widest)))
        $Private:Column.Width = New-DataGridPixelLength -Width $Private:Width
        $Private:Width
    }
}

function Get-DataGridColumnKey {
    <#
    .SYNOPSIS
        The name a column's values are read by: its sort member (what an auto-generated column is
        bound to), or else the path of its binding. Brackets around a path ([Some name]) are removed.

    .OUTPUTS
        [string], empty for a column that has neither (a template column).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        $Column
    )

    $Private:Key = [string]$Column.SortMemberPath
    if ([string]::IsNullOrWhiteSpace($Private:Key)) {
        $Private:Key = [string]$Column.Binding.Path.Path
    }
    return ($Private:Key -replace '^\[(.*)\]$', '$1')
}

function Get-DataGridColumnTextCandidate {
    <#
    .SYNOPSIS
        A column's longest values as text: the -Count longest, by length, of the longest line of each.

    .DESCRIPTION
        Only the longest few are measured, because measuring text in WPF costs far more than taking a
        length. In a proportional font the longest text is not always the widest, which is why it is a
        few rather than one.

        A row is a DataRowView (a DataTable's row, read by column name) or any object (read by
        property name). A value of DBNull or $null counts as empty.

    .OUTPUTS
        [string[]]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Row = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Key,

        [int]$Count = 3
    )

    if ([string]::IsNullOrWhiteSpace($Key)) {
        return
    }

    if (Initialize-DataGridColumnTextType) {
        return [Fortigi.DataGridColumnText]::Longest([object[]]@($Row), $Key, $Count)
    }

    # Without the compiled helper (it could not be built): the same in PowerShell, which is slow per
    # cell, so over at most 1,000 rows.
    $Private:Texts = [System.Collections.Generic.List[string]]::new()
    $Private:Lengths = [System.Collections.Generic.List[int]]::new()
    foreach ($Private:Item in @($Row | Select-Object -First 1000)) {
        $Private:Text = Get-DataGridCellText -Row $Private:Item -Key $Key
        if ($Private:Text.Length -gt 0) {
            $Private:Texts.Add($Private:Text)
            $Private:Lengths.Add($Private:Text.Length)
        }
    }

    $Private:TextArray = $Private:Texts.ToArray()
    $Private:LengthArray = $Private:Lengths.ToArray()
    [System.Array]::Sort($Private:LengthArray, $Private:TextArray)
    [System.Array]::Reverse($Private:TextArray)
    @($Private:TextArray | Select-Object -Unique | Select-Object -First $Count)
}

function Initialize-DataGridColumnTextType {
    <#
    .SYNOPSIS
        Builds, once per session, the compiled helper that finds a column's longest values.

    .DESCRIPTION
        Reading every cell of a result from PowerShell costs seconds for a few thousand rows of a few
        dozen columns, and this runs after every execute. The same loop in C# takes milliseconds, so
        it is compiled - as Initialize-OmadaSqltroubleShooter already compiles the tab strip's panel.
        It reads a DataRowView by column name and any other row (a PSCustomObject from a result) by
        property name, and keeps the -Count longest distinct texts, each the longest line of its value.

        When it cannot be built, $false - once: the failure is remembered for the session, so a broken
        build is not retried for every column of every result. The caller falls back to PowerShell.

    .OUTPUTS
        [bool] Whether the helper is there.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($null -ne ("Fortigi.DataGridColumnText" -as [type])) {
        return $true
    }
    if ($Script:DataGridColumnTextTypeFailed -eq $true) {
        return $false
    }

    try {
        # Add-Type's default references (.NET's reference set and PowerShell's own) cover everything the
        # helper uses; naming any assembly would replace them.
        Add-Type -ErrorAction Stop -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;

namespace Fortigi {
    public static class DataGridColumnText {
        public static string[] Longest(object[] rows, string key, int count) {
            var best = new List<string>();
            if (rows == null || string.IsNullOrEmpty(key) || count < 1) { return best.ToArray(); }
            foreach (object item in rows) {
                string text = LongestLine(Read(item, key));
                if (text.Length == 0 || best.Contains(text)) { continue; }
                if (best.Count < count) { best.Add(text); continue; }
                int shortest = 0;
                for (int i = 1; i < best.Count; i++) {
                    if (best[i].Length < best[shortest].Length) { shortest = i; }
                }
                if (text.Length > best[shortest].Length) { best[shortest] = text; }
            }
            best.Sort((a, b) => b.Length.CompareTo(a.Length));
            return best.ToArray();
        }

        private static string Read(object item, string key) {
            PSObject wrapped = item as PSObject;
            object row = wrapped != null ? wrapped.BaseObject : item;
            object value = null;
            DataRowView view = row as DataRowView;
            if (view != null) {
                if (view.Row.Table.Columns.Contains(key)) { value = view.Row[key]; }
            }
            else if (row != null) {
                PSPropertyInfo property = PSObject.AsPSObject(item).Properties[key];
                if (property != null) { value = property.Value; }
            }
            if (value == null || value is DBNull) { return string.Empty; }
            PSObject wrappedValue = value as PSObject;
            if (wrappedValue != null) { value = wrappedValue.BaseObject; }
            return Convert.ToString(value, CultureInfo.CurrentCulture) ?? string.Empty;
        }

        private static string LongestLine(string text) {
            if (text.IndexOf('\n') < 0) { return text; }
            string longest = string.Empty;
            foreach (string line in text.Split('\n')) {
                string trimmed = line.TrimEnd('\r');
                if (trimmed.Length > longest.Length) { longest = trimmed; }
            }
            return longest;
        }
    }
}
"@
        return $true
    }
    catch {
        $Script:DataGridColumnTextTypeFailed = $true
        "The column width helper could not be built; widths are measured in PowerShell: {0}" -f $_.Exception.Message | Write-LogOutput -LogType DEBUG
        return $false
    }
}

function Get-DataGridCellText {
    <#
    .SYNOPSIS
        One cell's value as the text that decides its width: the longest line, "" for no value.

    .DESCRIPTION
        A row is a DataRowView (a DataTable's row, read by column name) or any object (read by property
        name). DBNull and $null are no value.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Row,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $Private:Value = if ($Row -is [System.Data.DataRowView]) { $Row.Row[$Key] } else { $Row.$Key }
    if ($null -eq $Private:Value -or $Private:Value -is [System.DBNull]) {
        return ""
    }

    $Private:Text = [string]$Private:Value
    if ($Private:Text.Contains("`n")) {
        return @($Private:Text -split "\r?\n" | Sort-Object -Property Length -Descending)[0]
    }
    return $Private:Text
}

function Measure-DataGridText {
    <#
    .SYNOPSIS
        How wide a text is drawn in a grid's font, in device-independent pixels.

    .OUTPUTS
        [double]
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        $Grid,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return 0
    }

    $Private:Typeface = [System.Windows.Media.Typeface]::new($Grid.FontFamily, $Grid.FontStyle, $Grid.FontWeight, $Grid.FontStretch)
    $Private:PixelsPerDip = [System.Windows.Media.VisualTreeHelper]::GetDpi($Grid).PixelsPerDip
    $Private:Formatted = [System.Windows.Media.FormattedText]::new(
        $Text,
        [System.Globalization.CultureInfo]::CurrentUICulture,
        [System.Windows.FlowDirection]::LeftToRight,
        $Private:Typeface,
        $Grid.FontSize,
        [System.Windows.Media.Brushes]::Black,
        $Private:PixelsPerDip)
    return $Private:Formatted.WidthIncludingTrailingWhitespace
}

function New-DataGridPixelLength {
    <#
    .SYNOPSIS
        A DataGridLength of a fixed number of pixels; the width itself where WPF is not loaded (the
        tests).

    .OUTPUTS
        [System.Windows.Controls.DataGridLength] or [double]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [double]$Width
    )

    $Private:Type = "System.Windows.Controls.DataGridLength" -as [type]
    if ($null -eq $Private:Type) {
        return $Width
    }
    return $Private:Type::new($Width, [System.Windows.Controls.DataGridLengthUnitType]::Pixel)
}

function Update-DataGridColumnWidth {
    <#
    .SYNOPSIS
        Set-DataGridColumnWidth for a grid that has just been given its rows, where a failure must not
        stop the rows from showing: it is logged, and the columns keep the widths they had.

    .PARAMETER Grid
        The DataGrid.

    .PARAMETER Item
        The rows to measure, when not the grid's own (see Set-DataGridColumnWidth).

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Grid,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Item
    )

    if ($null -eq $Grid) {
        return
    }

    try {
        if ($PSBoundParameters.ContainsKey("Item")) {
            $null = Set-DataGridColumnWidth -Grid $Grid -Item $Item
        }
        else {
            $null = Set-DataGridColumnWidth -Grid $Grid
        }
    }
    catch {
        "Could not size the columns of grid '{0}': {1}" -f $Grid.Name, $_.Exception.Message | Write-LogOutput -LogType DEBUG
    }
}
