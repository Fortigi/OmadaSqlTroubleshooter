function ConvertTo-QueryPropertyList {
    <#
    .SYNOPSIS
        The name / value pairs the query details show for one query object.

    .DESCRIPTION
        Every field OData returned for the object, shown as the list shows it (ConvertTo-QueryManagerValue),
        except the OData annotations and the query text, which has its own tab. Then the creation and
        last change, taken from the object's history (Get-QueryHistorySummary), because OData does not
        return them.

    .PARAMETER Query
        The query object, as returned by GET C_P_SQLTROUBLESHOOTING(<id>).

    .PARAMETER HistoryEntry
        Its history, from ConvertTo-QueryHistoryEntry.

    .OUTPUTS
        [PSCustomObject] @{ Property; Value }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Query,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$HistoryEntry = @()
    )

    if ($null -ne $Query) {
        foreach ($Private:Property in $Query.PSObject.Properties) {
            if ($Private:Property.Name -like "@odata.*" -or $Private:Property.Name -eq "C_QUERY") {
                continue
            }
            [PSCustomObject]@{ Property = $Private:Property.Name; Value = ConvertTo-QueryManagerValue -Value $Private:Property.Value }
        }
    }

    $Private:Summary = Get-QueryHistorySummary -Entry $HistoryEntry
    [PSCustomObject]@{ Property = "Created (history)"; Value = ConvertTo-QueryManagerValue -Value $Private:Summary.Created }
    [PSCustomObject]@{ Property = "Created by (history)"; Value = [string]$Private:Summary.CreatedBy }
    [PSCustomObject]@{ Property = "Last changed (history)"; Value = ConvertTo-QueryManagerValue -Value $Private:Summary.Changed }
    [PSCustomObject]@{ Property = "Last changed by (history)"; Value = [string]$Private:Summary.ChangedBy }
}
