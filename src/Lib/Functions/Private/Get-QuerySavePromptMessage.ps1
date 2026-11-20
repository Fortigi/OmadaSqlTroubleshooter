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

        [switch]$ClosingApplication
    )

    switch ($Kind) {
        "SaveExisting" {
            return "Save changes to query '{0}' before closing?" -f $Name
        }
        "Unavailable" {
            return "'{0}' has unsaved changes that cannot be saved while the tab is disconnected. Close it anyway?" -f $Name
        }
    }

    $Private:Outcome = if ($ClosingApplication) {
        "If you don't save it, it is kept and offered again the next time the application starts."
    }
    else {
        "If you don't save it, it is lost."
    }

    return "'{0}' is an ad-hoc query that is not saved in Omada. Save it as a new query before closing?`n`n{1}" -f $Name, $Private:Outcome
}
