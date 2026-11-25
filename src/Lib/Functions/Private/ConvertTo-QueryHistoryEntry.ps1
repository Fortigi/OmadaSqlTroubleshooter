function ConvertTo-QueryHistoryEntry {
    <#
    .SYNOPSIS
        Turns a query object's raw change history into the entries the query details show.

    .DESCRIPTION
        One entry per change, newest first - every change, not only changes to the SQL text: the
        history window keeps only those, because it restores text, but a rename or a moved data
        connection belongs in the details too. Each entry names the fields the change touched.

    .PARAMETER Row
        The rows of a DataObjectHistory GetPagingData response (d.Rows): Who, What, When and
        ChangedFields, a JSON array of { Field, OldValue, NewValue }.

    .OUTPUTS
        [PSCustomObject] @{ When; Who; What; Fields }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Row = @()
    )

    $Private:Entries = foreach ($Private:Item in @($Row | Where-Object { $null -ne $_ })) {
        $Private:Fields = @()
        try {
            $Private:Fields = @(([string]$Private:Item.ChangedFields | ConvertFrom-Json -ErrorAction Stop) | ForEach-Object { $_.Field } | Where-Object { ![string]::IsNullOrWhiteSpace($_) })
        }
        catch {
            # A malformed ChangedFields still leaves who, what and when worth showing.
        }

        [PSCustomObject]@{
            When   = ConvertTo-OmadaHistoryDate -Value $Private:Item.When
            Who    = [string]$Private:Item.Who
            What   = [string]$Private:Item.What
            Fields = ($Private:Fields -join ", ")
        }
    }

    @($Private:Entries) | Sort-Object -Property @{ Expression = { if ($null -eq $_.When) { [DateTime]::MinValue } else { $_.When } }; Descending = $true }
}
