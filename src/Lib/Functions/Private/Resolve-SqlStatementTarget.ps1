function Resolve-SqlStatementTarget {
    <#
    .SYNOPSIS
        Decides, before anything is posted to Omada, which data connection each statement runs
        against and what text to post for it - or why the run cannot proceed at all.

    .DESCRIPTION
        The gate issue #152 puts in front of execution. It ties the three pure pieces together:
        Get-SqlDatabaseReference finds the database a statement addresses,
        Resolve-DataConnectionReference turns that name into the DoId the request needs, and
        ConvertTo-UnqualifiedSqlQuery produces the text that is safe to hand to SqlDataProducer.

        PER STATEMENT, NOT PER SCRIPT, and that is the whole shape of this function. Issue #151
        made every statement its own query against its own connection, so a script whose statements
        name different databases is no longer a contradiction - it is three queries against three
        connections, each with its own result grid. The earlier whole-script restriction existed
        only because the whole text used to be posted as one query; it is gone. What remains
        rejected is what cannot work: two databases inside ONE statement (#152 criterion 8), and a
        four-part linked-server name (criterion 10).

        The walk is IN ORDER because USE is sticky. A USE sets the current database for its own
        statement and every later one, exactly as in SSMS, and the last one still in force is
        applied to the dropdown afterwards (#152 open question 3, settled). An inline prefix binds
        only its own statement and leaves the dropdown alone.

        A USE-only statement rewrites to empty text and is DROPPED from the returned list. That is
        what makes "USE [X] alone switches the connection and executes nothing" fall out of the
        design rather than needing a status of its own: an empty list plus a pending switch IS that
        case, and the caller already has to handle "nothing to execute".

        NOTHING IS POSTED UNTIL THIS SAYS OK. Every rejection is decided here, with no HTTP call
        made and no data object written. The caller's contract is: on Rejected, show Message and
        stop.

        ScriptDom being unavailable yields None, not an error. The feature degrades to the behaviour
        that existed before it - every statement runs against whatever the dropdown has selected -
        because refusing to execute over a missing local convenience parser is the worse trade.

    .PARAMETER Statement
        The statements to resolve, as Get-SqlScriptStatement returns them: Ordinal, Text,
        StartOffset, Length. An empty list yields Status None.

    .PARAMETER OptionList
        The data connection entries to resolve against, each "{Name} - {DoId}". Omit to read them
        from the data connection dropdown, refreshing it once when it is empty (#152 section 4).

    .OUTPUTS
        [PSCustomObject] with

            Status       None      no statement addresses a database; execute exactly as before
                         Ok        at least one did; use Statement, and apply UseFullName if set
                         Rejected  do not execute; show Message
            Statement    the statements to execute, in order, each carrying the original fields plus
                         DatabaseName and DataConnectionDoId ($null = the selected connection) and
                         with Text rewritten free of prefixes and USE. Can be EMPTY when the script
                         was nothing but USE.
            UseFullName  the "{Name} - {DoId}" entry the dropdown must switch to, or $null
            UseDatabase  the database that switch names, or $null
            Message      the explanation to show, or $null
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyCollection()]
        $Statement,
        [Parameter(Mandatory = $false, Position = 1)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$OptionList
    )

    # No tracer preamble: the statements carry the user's query text (issue #61 section 5).

    $Result = [PSCustomObject]@{
        Status      = "None"
        Statement   = @($Statement)
        UseFullName = $null
        UseDatabase = $null
        Message     = $null
    }

    $Private:Input = @($Statement | Where-Object { $null -ne $_ })
    if ($Private:Input.Count -eq 0) {
        return $Result
    }

    # Read the reference of every statement FIRST, so a script that addresses no database at all
    # costs one parse per statement and then returns without ever touching the dropdown.
    $Private:Reference = [System.Collections.Generic.List[object]]::new()
    $Private:AddressesDatabase = $false

    foreach ($Private:Current in $Private:Input) {
        $Private:Found = Get-SqlDatabaseReference -SqlText $Private:Current.Text

        if ($Private:Found.Status -ne "Ok") {
            "The T-SQL parser is unavailable, so every statement runs against the selected data connection." | Write-LogOutput -LogType DEBUG
            return $Result
        }

        if ($null -ne $Private:Found.Rejection) {
            # The ordinal, because "the query addresses two databases" is not actionable in a script
            # of nine statements.
            $Result.Status = "Rejected"
            $Result.Message = "Statement {0}: {1}" -f $Private:Current.Ordinal, $Private:Found.Message
            return $Result
        }

        if (@($Private:Found.Database).Count -gt 0) {
            $Private:AddressesDatabase = $true
        }

        $Private:Reference.Add([PSCustomObject]@{ Statement = $Private:Current; Found = $Private:Found })
    }

    if (-not $Private:AddressesDatabase) {
        return $Result
    }

    if (!$PSBoundParameters.ContainsKey("OptionList")) {
        $OptionList = Get-DataConnectionOptionText
    }

    # The current database, as USE leaves it. Null until a USE says otherwise, which is what makes
    # an unprefixed statement before any USE run against the dropdown's selection.
    $Private:Current = $null
    $Private:CurrentFullName = $null
    $Private:CurrentName = $null

    $Private:Resolved = [System.Collections.Generic.List[object]]::new()

    foreach ($Private:Entry in $Private:Reference) {
        $Private:Found = $Private:Entry.Found
        $Private:Source = $Private:Entry.Statement

        # A USE replaces the current database for this statement and every later one.
        if (![string]::IsNullOrWhiteSpace($Private:Found.UseDatabase)) {
            $Private:Connection = Resolve-DataConnectionReference -Name $Private:Found.UseDatabase -OptionList $OptionList
            if ($null -eq $Private:Connection) {
                $Result.Status = "Rejected"
                $Result.Message = Get-UnresolvedDatabaseMessage -Ordinal $Private:Source.Ordinal -Database $Private:Found.UseDatabase -OptionList $OptionList
                return $Result
            }

            $Private:Current = $Private:Connection.DoId
            $Private:CurrentFullName = $Private:Connection.FullName
            $Private:CurrentName = $Private:Connection.Name
        }

        # An inline prefix binds this statement only. Get-SqlDatabaseReference has already rejected a
        # statement naming more than one, so there is at most one name here - and when the statement
        # is a bare USE it is the USE's own database, already resolved above.
        $Private:StatementDoId = $Private:Current
        $Private:StatementName = $Private:CurrentName

        $Private:Prefix = @($Private:Found.Database | Where-Object { $_ -ne $Private:Found.UseDatabase })
        if ($Private:Prefix.Count -gt 0) {
            $Private:Connection = Resolve-DataConnectionReference -Name $Private:Prefix[0] -OptionList $OptionList
            if ($null -eq $Private:Connection) {
                $Result.Status = "Rejected"
                $Result.Message = Get-UnresolvedDatabaseMessage -Ordinal $Private:Source.Ordinal -Database $Private:Prefix[0] -OptionList $OptionList
                return $Result
            }

            $Private:StatementDoId = $Private:Connection.DoId
            $Private:StatementName = $Private:Connection.Name
        }

        $Private:Rewritten = ConvertTo-UnqualifiedSqlQuery -SqlText $Private:Source.Text

        # Nothing left to run: a bare USE. Dropped, not kept as an empty statement, because an empty
        # statement would be posted to Omada and come back as a result grid with nothing in it.
        if ([string]::IsNullOrWhiteSpace($Private:Rewritten)) {
            continue
        }

        $Private:Resolved.Add([PSCustomObject][Ordered]@{
                Ordinal            = $Private:Source.Ordinal
                Text               = $Private:Rewritten
                StartOffset        = $Private:Source.StartOffset
                Length             = $Private:Source.Length
                DatabaseName       = $Private:StatementName
                DataConnectionDoId = $Private:StatementDoId
            })
    }

    $Result.Status = "Ok"
    $Result.Statement = @($Private:Resolved)
    $Result.UseFullName = $Private:CurrentFullName
    $Result.UseDatabase = $Private:CurrentName

    if ($Private:Resolved.Count -eq 0 -and ![string]::IsNullOrWhiteSpace($Private:CurrentName)) {
        $Result.Message = "Data connection changed to '{0}'. Nothing to execute." -f $Private:CurrentName
    }

    return $Result
}

function Get-DataConnectionOptionText {
    <#
    .SYNOPSIS
        The data connection dropdown's entries as plain "{Name} - {DoId}" strings, refreshed once if
        the list has not loaded yet.

    .DESCRIPTION
        Split out of Resolve-SqlStatementTarget so that function stays testable without WPF.

        The SYNCHRONOUS refresh pair, not Update-DataConnectionList. Since issue #90 that function is
        async-first: when a worker is eligible it dispatches and returns, and the list is repopulated
        later from the completion-poll timer. Calling it here would return before anything arrived,
        the re-read would still see an empty list, and a query naming a perfectly valid database
        would be rejected as unresolvable purely because it ran before the list had loaded. This is
        the same pair Update-DataConnectionList itself falls back to when no worker is available.

    .OUTPUTS
        [string[]] the dropdown entries, possibly empty.
    #>
    [CmdletBinding()]
    param()

    $Private:Option = @($Script:MainForm.Elements.ComboBoxSelectDataConnection.Items | ForEach-Object { [string]$_.Content })

    if (@($Private:Option | Where-Object { ![string]::IsNullOrWhiteSpace($_) }).Count -eq 0) {
        "The data connection list is empty; refreshing it synchronously before resolving the database." | Write-LogOutput -LogType DEBUG
        $Private:Inline = Get-DataConnectionPageInline
        Complete-DataConnectionListUpdate -DataObjectHtml $Private:Inline.Html -HasRows:$Private:Inline.HasRows -NotShowPopupWindow
        $Private:Option = @($Script:MainForm.Elements.ComboBoxSelectDataConnection.Items | ForEach-Object { [string]$_.Content })
    }

    return , @($Private:Option)
}

function Get-UnresolvedDatabaseMessage {
    <#
    .SYNOPSIS
        The message for a database name that matches no data connection (#152 criterion 9).

    .DESCRIPTION
        The available names are listed, because "unknown database" without them leaves the user
        guessing at the spelling of something only the tenant knows. One function because both the
        USE branch and the prefix branch produce the same message, and two copies would drift.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Ordinal,
        [Parameter(Mandatory = $true)]
        [string]$Database,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$OptionList
    )

    # Not wrapped in @() around the call - see the note in Update-SqlSchemaDatabaseTree.
    $Private:Reference = Get-DataConnectionReferenceList -OptionList $OptionList
    $Private:Available = @($Private:Reference.Name) | Where-Object { ![string]::IsNullOrWhiteSpace($_) }

    if (@($Private:Available).Count -eq 0) {
        return "Statement {0}: the database '{1}' cannot be resolved because no data connections are available. Connect to the tenant and try again." -f $Ordinal, $Database
    }

    return "Statement {0}: the database '{1}' does not match any data connection. Available: {2}." -f $Ordinal, $Database, (@($Private:Available) -join ", ")
}
