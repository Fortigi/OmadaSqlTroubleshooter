function Invoke-QueryDetailOpen {
    <#
    .SYNOPSIS
        The query details' Open and Open in new tab.

    .DESCRIPTION
        -InPlace opens the query in the active tab (Open-SqlQueryInActiveTab), otherwise in a new tab
        (Open-SqlQueryInTab). Once it is open the details and the query manager behind them close, so
        the tab can be seen. When it was not opened - cancelled at the save prompt, the tab not
        connected, or all tabs in use - both windows stay as they were.

    .PARAMETER InPlace
        Open in the active tab instead of a new one.

    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [switch]$InPlace
    )

    $Private:Query = $Script:QueryDetailForm.Query
    $Private:Tab = if ($InPlace) {
        Open-SqlQueryInActiveTab -DoId $Private:Query.DoId -DisplayName $Private:Query.DisplayName
    }
    else {
        Open-SqlQueryInTab -DoId $Private:Query.DoId -DisplayName $Private:Query.DisplayName
    }

    if ($null -ne $Private:Tab) {
        Request-QueryManagerClose
        $Script:QueryDetailForm.Definition.Close()
    }
}
