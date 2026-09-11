#Requires -Version 7.0
# The editor push seam is the one place where the user's query, the tenant's schema and the
# diagnostics built out of both are all handed to a function that opens with the tracer preamble.
#
# Issue #61 section 5 and acceptance criteria 8 and A10 say none of that may be written down, and
# redaction does not help: ConvertTo-RedactedLogString masks credentials and result data, not
# identifiers lifted out of a query or a schema. So Invoke-ExecuteScriptAsync traces the payload's
# SHAPE - the call, and how long the script was - and never its content.
#
# Asserted at the seam rather than per caller, because that is where it is enforced: a per-caller
# opt-out protects only the callers who remember it, and the next feature to push editor content
# would leak by omission.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Invoke-ExecuteScriptAsync.ps1")

    # A tracer that records instead of writing, so the assertions look at exactly what would have
    # reached System.Diagnostics.Trace.
    class RecordingTracer {
        static [System.Collections.Generic.List[string]]$Line = [System.Collections.Generic.List[string]]::new()
        static [void] WriteLine([string]$Message) {
            [RecordingTracer]::Line.Add($Message)
        }
    }

    $Script:Tracer = [RecordingTracer]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    # No WebView2 in a headless run. The function traces first and then finds nothing to push to,
    # which is precisely the part under test.
    $Script:Webview = @{ Object = $null }

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType = "INFO",
            $ErrorObject,
            [switch]$SkipDialog,
            [switch]$TabScoped
        )
        process { }
    }

    function Get-ActiveTabSession { return $null }
}

Describe 'Invoke-ExecuteScriptAsync tracing' -Tag 'Unit' {

    BeforeEach {
        [RecordingTracer]::Line.Clear()
    }

    It 'Should trace the call at all, so the assertions below are not passing on an empty trace' {
        Invoke-ExecuteScriptAsync -ScriptToExecute "setTheme('dark');"

        @([RecordingTracer]::Line).Count | Should -Be 1
        [RecordingTracer]::Line[0] | Should -Match 'Invoke-ExecuteScriptAsync'
    }

    It 'Should record the payload length rather than the payload' {
        $Script = "setTheme('dark');"

        Invoke-ExecuteScriptAsync -ScriptToExecute $Script

        [RecordingTracer]::Line[0] | Should -Match ("<{0} characters>" -f $Script.Length)
    }

    It 'Should never write <Label> into the trace' -ForEach @(
        @{ Label = 'the query text of an editor push'; Script = "setEditorValue('SELECT Zqx7Confidential FROM dbo.Zqx7SecretTable');" }
        @{ Label = 'the tenant schema of a setSchema push'; Script = 'setSchema({"Zqx7Schema":{"Zqx7Table":[{"n":"Zqx7Column","t":"nvarchar"}]}});' }
        @{ Label = 'the messages of a diagnostics push'; Script = 'setDiagnostics([{"message":"Incorrect syntax near ''Zqx7Confidential''.","source":"T-SQL syntax"}]);' }
    ) {
        Invoke-ExecuteScriptAsync -ScriptToExecute $Script

        foreach ($Entry in [RecordingTracer]::Line) {
            $Entry | Should -Not -Match 'Zqx7' -Because "'$Label' must not reach the trace"
            $Entry | Should -Not -Match 'SELECT'
            $Entry | Should -Not -Match 'Incorrect syntax'
        }
    }

    It 'Should say whether a completion block was supplied, without tracing it' {
        # Both arguments go through variables, and that is not tidiness. The preamble also writes
        # $MyInvocation.Statement, which is the SOURCE TEXT of the calling statement - so a literal
        # written at the call site is traced whatever this function does with its parameters. Every
        # real call site passes a variable or an expression, so nothing of the user's reaches it;
        # writing the literal here would fail this test for the test's own reason.
        $Script = "setTheme('dark');"
        $Completion = { "Zqx7Confidential" }

        Invoke-ExecuteScriptAsync -ScriptToExecute $Script -OnCompletedScriptBlock $Completion

        [RecordingTracer]::Line[0] | Should -Match '<scriptblock>'
        [RecordingTracer]::Line[0] | Should -Not -Match 'Zqx7'
    }

    It 'Should not trace a payload built at the call site either' {
        # The production call sites all look like this: an expression, never a literal. Asserted so
        # the guarantee is stated for the shape the application actually uses.
        $Table = "Zqx7SecretTable"
        Invoke-ExecuteScriptAsync -ScriptToExecute ("setEditorValue('SELECT * FROM dbo.{0}');" -f $Table)

        [RecordingTracer]::Line[0] | Should -Not -Match 'Zqx7'
    }

    It 'Should cope with a null payload rather than throwing on its length' {
        { Invoke-ExecuteScriptAsync -ScriptToExecute $null } | Should -Not -Throw
        [RecordingTracer]::Line[0] | Should -Match '<0 characters>'
    }

    It 'Should not hand the raw payload to ConvertTo-RedactedLogString at all' {
        # The discriminating assertion: redaction is not the defence here, because it does not mask
        # identifiers. The payload must never be given to it in the first place.
        $Source = Get-Content -Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "src\Lib\Functions\Private\Invoke-ExecuteScriptAsync.ps1") -Raw

        $Source | Should -Not -Match 'ConvertTo-RedactedLogString -InputObject \$PSBoundParameters'
    }
}
