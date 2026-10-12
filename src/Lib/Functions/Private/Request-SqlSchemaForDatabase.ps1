function Request-SqlSchemaForDatabase {
    <#
    .SYNOPSIS
        Serves the editor's request for the schema of a database named in the query.

    .DESCRIPTION
        The PowerShell end of issue #158 criterion 2. The editor knows which data connection names
        exist (setDatabaseNames) but not their DoIds, and it cannot make an authenticated request of
        its own, so a dot chain whose head is a database the editor has no model for posts
        { type: 'requestSchema', database: '<name>' } and this answers it.

        A name is matched against the DATA CONNECTION's name, not the physical database name. That is
        issue #152's open question 1, settled there deliberately: dataobjdlg.aspx exposes only name,
        DoId and uid, so there is no cheap way to ask a connection which database it points at. The
        same resolution the execute path uses is reused here - Resolve-DataConnectionReference over
        the dropdown entries - so what completes and what executes can never disagree about what
        "[Other]" means.

        It does NOT decide whether to make a request. Get-SqlSchemaObject owns the per-pool cache, the
        in-flight check and the background dispatch, so a database already cached is pushed back to
        the editor without touching the tenant (criterion 5), and two editors asking at once produce
        one request.

        A name that matches no data connection is logged at DEBUG and dropped. The user is typing: a
        half-written or simply wrong name is not a defect worth a dialog, and the execute path already
        reports an unresolvable database properly, with the available names (issue #152 criterion 9).

    .PARAMETER DatabaseName
        The name the editor saw, with brackets already stripped on the editor side.

    .OUTPUTS
        None.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DatabaseName
    )

    # No tracer preamble: the parameter names one of the tenant's databases (issue #61 section 5).

    try {
        if ([string]::IsNullOrWhiteSpace($DatabaseName)) {
            return
        }

        # -NoRefresh: this is reached from a keystroke in the editor. Refreshing the connection list
        # from the tenant synchronously here would block the window while the user is typing. If the
        # list has not loaded yet, cross-database completion simply does not work until it has -
        # which is the right trade for something that only ever adds suggestions.
        $Private:Connection = Resolve-DataConnectionReference -Name $DatabaseName -OptionList (Get-DataConnectionOptionText -NoRefresh)
        if ($null -eq $Private:Connection) {
            "The editor asked for the schema of a database that matches no data connection; ignoring." | Write-LogOutput -LogType DEBUG
            return
        }

        "The editor asked for the schema of data connection '{0}'." -f $Private:Connection.Name | Write-LogOutput -LogType DEBUG
        Get-SqlSchemaObject -DataConnectionDoId $Private:Connection.DoId -DataConnectionName $Private:Connection.Name
    }
    catch {
        $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
    }
}
