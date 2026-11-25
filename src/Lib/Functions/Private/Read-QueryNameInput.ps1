function Read-QueryNameInput {
    <#
    .SYNOPSIS
        Asks the user for a query name until they give a valid one or cancel.

    .DESCRIPTION
        Used to rename a query and to save an ad-hoc query. A name that Test-SqlQueryName refuses is
        asked for again, with the reason shown and what was typed kept, rather than ending the action:
        a typo should cost one correction, not starting over.

        Only the local checks happen here. Whether the tenant already has a query with that name is
        asked by the caller, once, with Test-SqlQueryNameTaken.

    .PARAMETER Title
        The dialog title.

    .PARAMETER Message
        What is being asked.

    .PARAMETER DefaultName
        The name the box starts with.

    .PARAMETER CurrentName
        The query's current name when renaming.

    .PARAMETER ExistingNames
        Names of the queries the tab knows.

    .PARAMETER OkText
        The text of the confirming button.

    .OUTPUTS
        [PSCustomObject] Test-SqlQueryName's result for the accepted name, or $null when cancelled.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$Title = "Query name",
        [string]$Message = "Name of the query:",
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DefaultName,
        [AllowNull()]
        [AllowEmptyString()]
        [string]$CurrentName,
        [AllowNull()]
        [string[]]$ExistingNames = @(),
        [string]$OkText = "Save"
    )

    $Private:Typed = $DefaultName
    $Private:Prompt = $Message

    while ($true) {
        $Private:Choice = Open-ChoiceForm -Title $Title -Message $Private:Prompt -LeftButtonText $OkText -RightButtonText "Cancel" -ShowInput -InputText $Private:Typed
        if ($Private:Choice -ne $true) {
            return $null
        }

        $Private:Typed = [string]$Script:ChoiceFormInputText
        $Private:Check = Test-SqlQueryName -Name $Private:Typed -ExistingNames $ExistingNames -CurrentName $CurrentName
        if ($Private:Check.IsValid) {
            return $Private:Check
        }

        $Private:Prompt = "{0}`n`n{1}" -f $Private:Check.Message, $Message
    }
}
