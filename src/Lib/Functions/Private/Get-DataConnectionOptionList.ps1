function Get-DataConnectionOptionList {
    <#
    .SYNOPSIS
    Parses the Omada dataobjdlg.aspx HTML into the ordered, de-duplicated list of data connection
    display names ("{DisplayName} - {DoId}") shown in the data connection dropdown.

    .DESCRIPTION
    Extracted from Update-DataConnectionList so the fiddly option-matching can be unit tested. Each
    <option> carries the connection DoId in value="", its uid in data-uid="" and its name as the
    element text; the dropdown shows "{name} - {DoId}". Order is preserved and duplicates are dropped.
    #>
    [CmdLetBinding()]
    param(
        [string]$Html
    )

    $Result = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($Html)) {
        return , $Result.ToArray()
    }

    $Options = [regex]::Matches($Html, '<option.*?value="(\d+).*?data-uid="(.*?)".*?>(.*?)</option>')
    foreach ($Match in $Options) {
        $DisplayName = "{0} - {1}" -f $Match.Groups[3].Value, $Match.Groups[1].Value
        if (-not $Result.Contains($DisplayName)) {
            $Result.Add($DisplayName)
        }
    }

    return , $Result.ToArray()
}
