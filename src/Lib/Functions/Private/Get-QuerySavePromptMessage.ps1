function Get-QuerySavePromptMessage {
    <#
    .SYNOPSIS
        What the user is asked when a tab with unsaved query changes is closed.

    .DESCRIPTION
        Says which query, whether saving updates it or creates a new one, and what happens to an
        ad-hoc query that is not saved - which differs: closing one tab throws it away, closing the
        application keeps it in the draft cache and offers it again at the next start.

    .PARAMETER Kind
        Resolve-QuerySavePrompt's answer.

    .PARAMETER Name
        The tab's name.

    .PARAMETER ClosingApplication
        The whole application is closing, not one tab.

    .PARAMETER NewQuery
        The editor is about to be cleared for a new query (New), not closed.

    .PARAMETER OpenQuery
        Another query is about to be opened in the tab, in place of this one.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("SaveExisting", "SaveNew", "Unavailable")]
        [string]$Kind,

        [string]$Name,

        [switch]$ClosingApplication,

        [switch]$NewQuery,

        [switch]$OpenQuery
    )

    $Private:Moment = if ($OpenQuery) { "before opening another query" } elseif ($NewQuery) { "before starting a new query" } else { "before closing" }

    switch ($Kind) {
        "SaveExisting" {
            return "Save changes to query '{0}' {1}?" -f $Name, $Private:Moment
        }
        "Unavailable" {
            $Private:Anyway = if ($NewQuery -or $OpenQuery) { "Discard them anyway?" } else { "Close it anyway?" }
            return "'{0}' has unsaved changes that cannot be saved while the tab is disconnected. {1}" -f $Name, $Private:Anyway
        }
    }

    $Private:Outcome = if ($ClosingApplication) {
        "If you don't save it, it is kept and offered again the next time the application starts."
    }
    else {
        "If you don't save it, it is lost."
    }

    return "'{0}' is an ad-hoc query that is not saved in Omada. Save it as a new query {1}?`n`n{2}" -f $Name, $Private:Moment, $Private:Outcome
}
