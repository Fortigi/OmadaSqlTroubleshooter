function Resolve-SqlDatabaseTarget {
    <#
    .SYNOPSIS
        Decides, before anything is posted to Omada, which data connection a query must run against
        and what text to post - or why it cannot run at all.

    .DESCRIPTION
        The single gate issue #152 puts in front of execution. It ties the three pure pieces
        together: Get-SqlDatabaseReference finds the databases the script addresses,
        Resolve-DataConnectionReference turns a name into the DoId the request needs, and
        ConvertTo-UnqualifiedSqlQuery produces the text that is safe to hand to SqlDataProducer.

        NOTHING IS POSTED UNTIL THIS SAYS OK. An unknown database name, a cross-database query and a
        four-part name are all decided here, with no HTTP call made and no data object written
        (#152 criteria 8, 9, 10). The caller's contract is simply: on Rejected, show Message and
        stop.

        A query that addresses no database at all returns None, and the caller changes nothing about
        how it executes. That is what keeps #152 criterion 14 true - a query with no prefix costs one
        local parse and not a single extra request.

        ScriptDom not being loaded is also None, not an error. The feature degrades to the behaviour
        that existed before it: the query runs against whatever the dropdown has selected. Refusing
        to execute because a local convenience parser is missing would be a worse trade than running
        the query the user actually asked for.

    .PARAMETER SqlText
        The text that will actually be executed - the selection in selection-execution mode, the
        whole editor otherwise. Both go through the identical path (#152 criterion 11).

    .PARAMETER OptionList
        The data connection entries to resolve against, each "{Name} - {DoId}". Omit to read them
        from the data connection dropdown, refreshing it once via Update-DataConnectionList when it
        is empty (#152 section 4).

    .OUTPUTS
        [PSCustomObject] with

            Status         None       no database is addressed; execute exactly as before
                           Ok         a database resolved; use TargetDoId and RewrittenText
                           SwitchOnly a bare USE; make the switch stick, show Message, post nothing
                           Rejected   do not execute; show Message
            TargetDoId     the resolved data connection's DoId, or $null
            TargetName     the resolved data connection's name, or $null
            TargetFullName the "{Name} - {DoId}" entry, for Set-ConfigProperty
            RewrittenText  the text to post, prefixes and USE removed, or $null
            UseDatabase    the database named by USE, or $null - the caller makes this stick
            Message        the explanation to show, or $null
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlText,
        [Parameter(Mandatory = $false, Position = 1)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$OptionList
    )

    # No tracer preamble: the first parameter is the user's query (issue #61 section 5).

    $Result = [PSCustomObject]@{
        Status         = "None"
        TargetDoId     = $null
        TargetName     = $null
        TargetFullName = $null
        RewrittenText  = $null
        UseDatabase    = $null
        Message        = $null
    }

    $Reference = Get-SqlDatabaseReference -SqlText $SqlText
    if ($Reference.Status -ne "Ok") {
        "The T-SQL parser is unavailable, so the query runs against the selected data connection." | Write-LogOutput -LogType DEBUG
        return $Result
    }

    if ($null -ne $Reference.Rejection) {
        $Result.Status = "Rejected"
        $Result.Message = $Reference.Message
        return $Result
    }

    if (@($Reference.Database).Count -eq 0) {
        return $Result
    }

    # Get-SqlDatabaseReference has already rejected anything naming more than one, so there is
    # exactly one name here.
    $Name = @($Reference.Database)[0]

    if (!$PSBoundParameters.ContainsKey("OptionList")) {
        $OptionList = @($Script:MainForm.Elements.ComboBoxSelectDataConnection.Items | ForEach-Object { [string]$_.Content })

        if (@($OptionList | Where-Object { ![string]::IsNullOrWhiteSpace($_) }).Count -eq 0) {
            # Not yet populated rather than genuinely empty: refresh once before deciding that a
            # name cannot be resolved, so a query executed early in the session is not rejected for
            # a list that simply had not loaded.
            #
            # The SYNCHRONOUS pair, not Update-DataConnectionList. Since #90 that function is
            # async-first: when a worker is eligible it dispatches and returns, and the list is
            # repopulated later from the completion-poll timer. Calling it here would therefore
            # return before anything arrived, the re-read below would still see an empty list, and a
            # query naming a perfectly valid database would be rejected with "no data connections
            # are available" purely because it ran before the list had loaded. This is the same pair
            # Update-DataConnectionList itself falls back to when no worker is available.
            "The data connection list is empty; refreshing it synchronously before resolving the database." | Write-LogOutput -LogType DEBUG
            $Private:Inline = Get-DataConnectionPageInline
            Complete-DataConnectionListUpdate -DataObjectHtml $Private:Inline.Html -HasRows:$Private:Inline.HasRows -NotShowPopupWindow
            $OptionList = @($Script:MainForm.Elements.ComboBoxSelectDataConnection.Items | ForEach-Object { [string]$_.Content })
        }
    }

    $Connection = Resolve-DataConnectionReference -Name $Name -OptionList $OptionList
    if ($null -eq $Connection) {
        # The available names are listed, because "unknown database" without them leaves the user
        # guessing at the spelling of something only the tenant knows (#152 criterion 9).
        $Available = @($OptionList | ForEach-Object { if ($_ -match '^(?<Name>.*) - (?<DoId>\d+)$') { $Matches.Name } }) | Where-Object { ![string]::IsNullOrWhiteSpace($_) }

        $Result.Status = "Rejected"
        if (@($Available).Count -eq 0) {
            $Result.Message = "The database '{0}' cannot be resolved: no data connections are available. Connect to the tenant and try again." -f $Name
        }
        else {
            $Result.Message = "The database '{0}' does not match any data connection. Available: {1}." -f $Name, (@($Available) -join ", ")
        }
        return $Result
    }

    $Result.TargetDoId = $Connection.DoId
    $Result.TargetName = $Connection.Name
    $Result.TargetFullName = $Connection.FullName
    $Result.RewrittenText = ConvertTo-UnqualifiedSqlQuery -SqlText $SqlText
    if (![string]::IsNullOrWhiteSpace($Reference.UseDatabase)) {
        $Result.UseDatabase = $Connection.Name
    }

    # "USE [X]" on its own leaves nothing to run. SSMS switches the current database and reports it
    # rather than executing an empty batch, and so does this: the caller makes the switch stick and
    # writes the message, and no query is posted (#152 section 2).
    if ([string]::IsNullOrWhiteSpace($Result.RewrittenText)) {
        $Result.Status = "SwitchOnly"
        $Result.Message = "Data connection changed to '{0}'. Nothing to execute." -f $Connection.Name
        return $Result
    }

    $Result.Status = "Ok"
    return $Result
}
