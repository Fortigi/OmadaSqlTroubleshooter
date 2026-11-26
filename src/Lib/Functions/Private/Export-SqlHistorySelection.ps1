function Export-SqlHistorySelection {
    <#
    .SYNOPSIS
        The history window's "Export selected query" and "Export selected diff": saves the selected
        version's new SQL, or its diff against the version before it, to a file the user picks.

    .DESCRIPTION
        One version at a time, the one the selection is in (Get-SqlHistorySelectedItem); a selection
        over none or several asks for one. The file name offered is
        SQL_History_<query name>_<change date>_query (.sql) or ..._diff (.diff), see
        Get-SqlHistoryExportFileName. The diff is the one the Diff View tab shows, as text
        (ConvertTo-HistoryDiffText).

    .PARAMETER Kind
        Query or Diff.

    .OUTPUTS
        [string] The file written, or $null when nothing was.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Query", "Diff")]
        [string]$Kind
    )

    $Private:Item = Get-SqlHistorySelectedItem
    if ($null -eq $Private:Item) {
        "Select one version (a row, or cells in one row) to export." | Write-LogOutput -LogType WARNING
        return $null
    }

    $Private:FileName = Get-SqlHistoryExportFileName -QueryName $Private:Item.SqlObjectName -ChangeDate $Private:Item.ChangeDate -Kind $Kind
    $Private:Format = if ($Kind -eq "Query") {
        @{ Title = "Export selected query"; Filter = "SQL files (*.sql)|*.sql|Text files (*.txt)|*.txt|All files (*.*)|*.*"; Extension = ".sql" }
    }
    else {
        @{ Title = "Export selected diff"; Filter = "Diff files (*.diff)|*.diff|Text files (*.txt)|*.txt|All files (*.*)|*.*"; Extension = ".diff" }
    }

    $Private:Path = Request-SqlHistoryExportPath -Title $Private:Format.Title -FileName $Private:FileName -Filter $Private:Format.Filter -Extension $Private:Format.Extension
    if ([string]::IsNullOrWhiteSpace($Private:Path)) {
        return $null
    }

    $Private:Content = if ($Kind -eq "Query") {
        [string]$Private:Item.NewValue
    }
    else {
        ConvertTo-HistoryDiffText -OldValue $Private:Item.OldValue -NewValue $Private:Item.NewValue -QueryName $Private:Item.SqlObjectName -ChangeDate $Private:Item.ChangeDate
    }

    Set-Content -Path $Private:Path -Value $Private:Content -Encoding UTF8 -NoNewline
    "SQL history {0} exported to: {1}" -f $Kind.ToLowerInvariant(), $Private:Path | Write-LogOutput
    return $Private:Path
}

function Get-SqlHistoryExportFileName {
    <#
    .SYNOPSIS
        The file name the history window's exports offer, without extension:
        SQL_History_<query name>_<change date>_<kind>.

    .DESCRIPTION
        The change date is yyyyMMdd_HHmmss, so the names sort in time order; "unknown-date" when the
        version's date could not be read (issue #95). Characters a Windows file name cannot hold, and
        whitespace, become underscores, so a query named "Accounts: open / closed" still gives a name
        the save dialog accepts.

    .PARAMETER QueryName
        The query's name.

    .PARAMETER ChangeDate
        The version's change date.

    .PARAMETER Kind
        query, diff or all.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$QueryName,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $ChangeDate,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Query", "Diff", "All")]
        [string]$Kind
    )

    $Private:Name = (([string]$QueryName).Trim() -replace '[\\/:*?"<>|\s]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($Private:Name)) {
        $Private:Name = "query"
    }

    $Private:Date = if ($ChangeDate -is [DateTime]) { $ChangeDate.ToString("yyyyMMdd_HHmmss", [System.Globalization.CultureInfo]::InvariantCulture) } else { "unknown-date" }
    return "SQL_History_{0}_{1}_{2}" -f $Private:Name, $Private:Date, $Kind.ToLowerInvariant()
}

function ConvertTo-HistoryDiffText {
    <#
    .SYNOPSIS
        A version's diff as text: the comparison the Diff View tab shows (Invoke-GenerateDiffView),
        written as lines that start with "-", "+" or a space.

    .DESCRIPTION
        The Diff View compares the old and the new text line by line, by position. So does this:

          "  line"           the same in both
          "- old" / "+ new"  changed: the old line, then the new one
          "+ new"            only in the new text (the old has fewer lines, or an empty one there)
          "- old"            only in the old text

        Two header lines name the query and the version, as a unified diff's do.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$OldValue,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$NewValue,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$QueryName,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $ChangeDate
    )

    # @() around the if: an if that yields a one-line array would otherwise hand back the bare string.
    $Private:OldLines = @(if ([string]::IsNullOrWhiteSpace($OldValue)) { } else { $OldValue -split "\r?\n" })
    $Private:NewLines = @(if ([string]::IsNullOrWhiteSpace($NewValue)) { } else { $NewValue -split "\r?\n" })
    $Private:When = if ($ChangeDate -is [DateTime]) { $ChangeDate.ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture) } else { "(unknown date)" }

    $Private:Lines = [System.Collections.Generic.List[string]]::new()
    $Private:Lines.Add(("--- {0} (before the change of {1})" -f $QueryName, $Private:When))
    $Private:Lines.Add(("+++ {0} ({1})" -f $QueryName, $Private:When))

    for ($Private:Index = 0; $Private:Index -lt [Math]::Max($Private:OldLines.Count, $Private:NewLines.Count); $Private:Index++) {
        $Private:Old = if ($Private:Index -lt $Private:OldLines.Count) { $Private:OldLines[$Private:Index] } else { "" }
        $Private:New = if ($Private:Index -lt $Private:NewLines.Count) { $Private:NewLines[$Private:Index] } else { "" }
        foreach ($Private:Line in @(ConvertTo-HistoryDiffLine -Old $Private:Old -New $Private:New)) {
            $Private:Lines.Add($Private:Line)
        }
    }

    return ($Private:Lines -join [Environment]::NewLine) + [Environment]::NewLine
}

function ConvertTo-HistoryDiffLine {
    <#
    .SYNOPSIS
        The diff line(s) for one line position, by the Diff View's rules.

    .OUTPUTS
        [string[]]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Old = "",

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$New = ""
    )

    if ($Old -ceq $New) {
        return "  {0}" -f $Old
    }
    if ([string]::IsNullOrEmpty($Old)) {
        return "+ {0}" -f $New
    }
    if ([string]::IsNullOrEmpty($New)) {
        return "- {0}" -f $Old
    }
    "- {0}" -f $Old
    "+ {0}" -f $New
}

function Request-SqlHistoryExportPath {
    <#
    .SYNOPSIS
        Asks where to save an export, offering a file name.

    .OUTPUTS
        [string] The path chosen, or $null when the dialog was cancelled.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [string]$Filter,

        [Parameter(Mandatory = $true)]
        [string]$Extension
    )

    $Private:Dialog = New-Object Microsoft.Win32.SaveFileDialog
    $Private:Dialog.Title = $Title
    $Private:Dialog.Filter = $Filter
    $Private:Dialog.DefaultExt = $Extension
    $Private:Dialog.FileName = $FileName

    # See Suspend-WebViewCompletionPolling.ps1 - ShowDialog() pumps this thread's messages while it
    # blocks, which could let the WebView2 completion poll timer fire reentrantly.
    Suspend-WebViewCompletionPolling
    try {
        $Private:Chosen = $Private:Dialog.ShowDialog()
    }
    finally {
        Resume-WebViewCompletionPolling
    }
    return $(if ($Private:Chosen -eq $true) { $Private:Dialog.FileName } else { $null })
}

function Get-SqlHistoryQueryUId {
    <#
    .SYNOPSIS
        The UId of the query a history version belongs to, for the history window's Details tab.

    .DESCRIPTION
        The history rows carry the query's id, not its UId. The window that opened the history may
        already know it (the query details pass it in, $Script:SqlHistoryTarget.UId); otherwise the
        query object is read from OData once, and the answer kept for the window (a version's query
        is the same for every version).

    .PARAMETER DoId
        The query's id.

    .OUTPUTS
        [string] The UId, or "" when it cannot be read.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$DoId
    )

    if ([string]::IsNullOrWhiteSpace($DoId)) {
        return ""
    }
    if ($null -ne $Script:SqlHistoryTarget -and [string]$Script:SqlHistoryTarget.DoId -eq $DoId -and -not [string]::IsNullOrWhiteSpace([string]$Script:SqlHistoryTarget.UId)) {
        return [string]$Script:SqlHistoryTarget.UId
    }
    if ($null -ne $Script:SqlHistoryQueryUIdCache -and $Script:SqlHistoryQueryUIdCache.DoId -eq $DoId) {
        return $Script:SqlHistoryQueryUIdCache.UId
    }

    $Private:Response = Invoke-SavedQueryRequest -Request (New-QueryManagerRequest -Kind "QueryObject" -Context @{ BaseUrl = $Script:AppConfig.BaseUrl; QueryDoId = $DoId })
    $Private:UId = if ($Private:Response.Succeeded) { [string]$Private:Response.Result.UId } else { "" }
    $Script:SqlHistoryQueryUIdCache = [PSCustomObject]@{ DoId = $DoId; UId = $Private:UId }
    return $Private:UId
}

function Find-SqlHistoryItemIndex {
    <#
    .SYNOPSIS
        Where in the history window's list the version of a history entry is: same change date, same
        user. -1 when it is not there.

    .DESCRIPTION
        The query details' History tab lists every change of a query; the history window lists only
        the ones that changed its SQL. Both are read from the same history rows, with the same date
        conversion, so the date and the user identify a version. A change that did not touch the SQL
        (a rename) has no version in the window: -1.

    .PARAMETER Item
        The window's versions.

    .PARAMETER ChangeDate
        The entry's date.

    .PARAMETER ChangedBy
        The entry's user.

    .OUTPUTS
        [int]
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Item = @(),

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $ChangeDate,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$ChangedBy
    )

    if ($null -eq $ChangeDate) {
        return -1
    }

    $Private:Items = @($Item)
    for ($Private:Index = 0; $Private:Index -lt $Private:Items.Count; $Private:Index++) {
        $Private:Version = $Private:Items[$Private:Index]
        if ($Private:Version.ChangeDate -eq $ChangeDate -and [string]$Private:Version.ChangedBy -eq $ChangedBy) {
            return $Private:Index
        }
    }
    return -1
}
