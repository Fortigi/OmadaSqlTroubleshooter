function Update-SqlSyntaxDiagnostic {
    <#
    .SYNOPSIS
        Runs the T-SQL syntax pass over the active tab's editor content and pushes the result into
        the editor's diagnostics channel.

    .DESCRIPTION
        Reads the editor content over the existing Invoke-ExecuteScriptWithResultAsync seam, parses
        it with ScriptDom, and pushes markers back through setDiagnostics. Nothing here contacts
        Omada: there is no Invoke-OmadaPSWebRequestWrapper on this path, and no other request either
        (issue #61 acceptance criterion 5).

        The read and the push are both asynchronous and go through the WebView2 completion poll
        timer, so the WPF dispatcher is never blocked and the WebView2 suspend/resume rules
        Invoke-OmadaPSWebRequestWrapper documents are respected by construction.

    .PARAMETER SqlText
        Parse this text instead of reading the editor. Used by the execute path, which already has
        the script in hand and must not pay for a second round trip to the WebView.

    .OUTPUTS
        None. Markers are pushed to the editor; nothing is returned or persisted.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SqlText
    )

    # No tracer preamble: $SqlText is the user's query (issue #61 section 5).

    try {
        $Setting = Get-SqlValidationSetting
        if (-not $Setting.Enabled) {
            return
        }

        if ($PSBoundParameters.ContainsKey("SqlText")) {
            $Result = Get-SqlSyntaxDiagnostic -SqlText $SqlText -ParserVersion $Setting.ParserVersion
            if ($Result.Status -ne "Ok") {
                return
            }

            Invoke-ExecuteScriptAsync -ScriptToExecute (ConvertTo-EditorDiagnosticScript -Diagnostic $Result.Diagnostic)
            return
        }

        # A plain scriptblock, never .GetNewClosure(): the completion poll timer in
        # MainForm.Definition.ps1 is what invokes it, and a closure block runs in a detached dynamic
        # module that cannot resolve this module's dot-sourced private functions.
        $OnCompletedScriptBlock = {
            try {
                if ($Script:Task.Status -ne "RanToCompletion") {
                    return
                }

                $EditorText = $Script:Task.Result | ConvertFrom-Json
                Update-SqlSyntaxDiagnostic -SqlText ([string]$EditorText)
            }
            catch {
                # Never surfaced to the user: a failed background validation must not interrupt
                # typing. The message can quote the script, so it is not logged.
                "Reading the editor content for syntax validation failed." | Write-LogOutput -LogType DEBUG
            }
        }

        Invoke-ExecuteScriptWithResultAsync -ScriptToExecute "editor.getValue();" -OnCompletedScriptBlock $OnCompletedScriptBlock
    }
    catch {
        "Syntax validation could not run for this change." | Write-LogOutput -LogType DEBUG
    }
}
