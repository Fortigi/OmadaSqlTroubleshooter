function Update-SqlSyntaxDiagnostic {
    <#
    .SYNOPSIS
        Runs the client-side validation passes over the active tab's editor content and pushes the
        result into the editor's diagnostics channel.

    .DESCRIPTION
        Reads the editor content over the existing Invoke-ExecuteScriptWithResultAsync seam, checks it
        with Get-SqlDiagnostic - syntax, schema and Omada compatibility from a single parse - and
        pushes the markers back through setDiagnostics. Nothing here contacts Omada: there is no
        Invoke-OmadaPSWebRequestWrapper on this path, and no other request either. The schema pass
        resolves against the cache the editor's IntelliSense already filled (issue #61 acceptance
        criterion 5).

        The name is unchanged from when this ran one pass. It is what MainForm.Definition.ps1's
        debounce timer and Get-SqlSchema.ps1's post-push trigger call, and renaming it would touch
        three files to say the same thing.

        The read and the push are both asynchronous and go through the WebView2 completion poll
        timer, and the WebView2 suspend/resume rules Invoke-OmadaPSWebRequestWrapper documents are
        respected by construction.

        The CHECK runs on a worker (issue #185). The read's completion block runs on the dispatcher,
        and the parse plus the schema and Omada passes used to run right there with it - hundreds of
        milliseconds to seconds of a frozen window after every pause in typing. The debounced path
        now hands the text to Start-SqlDiagnosticBackground and returns; the markers arrive through
        the same completion queue once the worker is done. When no worker is available it validates
        inline, exactly as it used to.

    .PARAMETER SqlText
        Check this text instead of reading the editor. Used by the execute path, which already has
        the script in hand and must not pay for a second round trip to the WebView.

    .PARAMETER Background
        Check the text on a worker rather than inline. Only the debounced path sets it; the execute
        path needs its answer before it can decide whether to ask the user, so it stays inline.

    .OUTPUTS
        None. Markers are pushed to the editor; nothing is returned or persisted.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlText,

        [Parameter(Mandatory = $false)]
        [switch]$Background
    )

    # No tracer preamble: $SqlText is the user's query (issue #61 section 5).

    try {
        $Setting = Get-SqlValidationSetting
        if (-not $Setting.Enabled -and -not $Setting.SchemaEnabled -and -not $Setting.OmadaEnabled) {
            return
        }

        if ($PSBoundParameters.ContainsKey("SqlText")) {
            $TabSession = Get-ActiveTabSession

            # On a worker when asked and when one is available; otherwise inline, as it always was.
            if ($Background -and $null -ne (Start-SqlDiagnosticForTab -TabSession $TabSession -SqlText $SqlText -Setting $Setting)) {
                return
            }

            # Whatever this tab's worker is still computing is about text older than this, so it is
            # stopped before these markers go on screen - otherwise it could land on top of them.
            Stop-SqlDiagnosticBackground -TabSession $TabSession

            $Result = Get-SqlDiagnostic -SqlText $SqlText -Setting $Setting

            # A check that could not run clears the markers rather than leaving them. Anything still
            # on screen came from an EARLIER check of DIFFERENT text, so leaving it would keep
            # asserting something about a script nobody looked at - and the user cannot tell a stale
            # squiggle from a live one. An empty set is what ConvertTo-EditorDiagnosticScript turns
            # into a clearing call.
            $Diagnostic = @()
            if ($Result.Status -eq "Ok") {
                $Diagnostic = $Result.Diagnostic
            }

            Invoke-ExecuteScriptAsync -ScriptToExecute (ConvertTo-EditorDiagnosticScript -Diagnostic $Diagnostic)
            return
        }

        # A plain scriptblock, never .GetNewClosure(): the completion poll timer in
        # MainForm.Definition.ps1 is what invokes it, and a closure block runs in a detached dynamic
        # module that cannot resolve this module's dot-sourced private functions.
        $OnCompletedScriptBlock = {
            try {
                if ($Script:Task.Status -ne "RanToCompletion") {
                    # The read did not produce text, so nothing was checked - and the same rule
                    # applies here as to a check that could not run: what is on screen came from an
                    # EARLIER check of DIFFERENT text, and the user cannot tell a stale squiggle from
                    # a live one.
                    Clear-SqlEditorDiagnostic
                    return
                }

                $EditorText = $Script:Task.Result | ConvertFrom-Json
                Update-SqlSyntaxDiagnostic -SqlText ([string]$EditorText) -Background
            }
            catch {
                # Never surfaced to the user: a failed background validation must not interrupt
                # typing. The message can quote the script, so it is not logged.
                "Reading the editor content for validation failed." | Write-LogOutput -LogType DEBUG
                Clear-SqlEditorDiagnostic
            }
        }

        Invoke-ExecuteScriptWithResultAsync -ScriptToExecute "editor.getValue();" -OnCompletedScriptBlock $OnCompletedScriptBlock
    }
    catch {
        "Validation could not run for this change." | Write-LogOutput -LogType DEBUG
    }
}

function Clear-SqlEditorDiagnostic {
    <#
    .SYNOPSIS
        Removes every client-side validation marker from the editor.

    .DESCRIPTION
        The one rule this whole path follows: a check that COULD NOT RUN clears the markers rather
        than leaving them. Whatever is on screen came from an earlier check of different text, and a
        stale squiggle is indistinguishable from a live one - so leaving it keeps asserting something
        about a script nobody looked at.

        Written down as a function because there are now three places that need it - the two
        "could not run" exits of the debounced editor read, and the direct path above, which does the
        same thing inline because it already has the empty set in hand. A rule stated three times is a
        rule two of them can drift from.

        It can never throw. It is called from a catch block on a background completion, and a failure
        to tidy up must not become a second failure on top of the first.

    .OUTPUTS
        None.
    #>
    [CmdLetBinding()]
    param()

    # No tracer preamble: this is on the debounced validation path (issue #61 section 5).

    try {
        Invoke-ExecuteScriptAsync -ScriptToExecute (ConvertTo-EditorDiagnosticScript -Diagnostic @())
    }
    catch {
        "The editor diagnostics could not be cleared." | Write-LogOutput -LogType DEBUG
    }
}
