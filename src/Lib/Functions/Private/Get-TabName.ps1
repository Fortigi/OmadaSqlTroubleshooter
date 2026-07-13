function Get-TabName {
    <#
    .SYNOPSIS
    Determines a tab's base name (the "<Tabname>" part of the header, before the dirty marker,
    data connection and tenant are appended by Update-TabHeaderTitle).

    .DESCRIPTION
    Resolution order (first match wins):
      1. The selected value of ComboBoxSelectQuery, when a query is selected.
      2. The TextBoxDisplayName value, when it is not empty.
      3. "Query{#}", where # is the order in which the tab was opened (first opened tab = Query1).

    Reads from the tab's own Elements so it is correct for any tab, not just the active one.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TabSession
    )
    try {
        $Elements = $TabSession.Elements

        $SelectedQuery = $null
        if ($null -ne $Elements.ComboBoxSelectQuery.SelectedItem) {
            $SelectedQuery = $Elements.ComboBoxSelectQuery.SelectedItem.Content
        }
        if ([string]::IsNullOrWhiteSpace($SelectedQuery)) {
            $SelectedQuery = $Elements.ComboBoxSelectQuery.Text
        }
        if (![string]::IsNullOrWhiteSpace($SelectedQuery)) {
            # The selected item's content is the query FullName ("<DisplayName> - <DoId>"); the tab
            # shows the name WITHOUT its trailing DoId. The DoId is always the final " - <digits>"
            # segment, so stripping only that is safe even for a name that itself contains
            # " - <number>".
            return (($SelectedQuery.ToString().Trim()) -replace "\s*-\s*\d+\s*$", "")
        }

        $DisplayName = $Elements.TextBoxDisplayName.Text
        if (![string]::IsNullOrWhiteSpace($DisplayName)) {
            return $DisplayName.ToString().Trim()
        }

        $Order = if ($null -ne $TabSession.OpenOrder) { $TabSession.OpenOrder } else { 1 }
        return "Query{0}" -f $Order
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        return "Query"
    }
}
