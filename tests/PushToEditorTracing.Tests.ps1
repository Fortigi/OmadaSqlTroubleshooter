#Requires -Version 7.0
# Issue #111: Push-ToEditor's parameter IS the payload, and the payload is built out of the user's own
# text - Set-EditorValue interpolates a saved query straight into "window.setEditorValue('...')", so
# opening a query wrote that query into the trace. The log window has an Export Log File button, so
# whatever lands there is one click from leaving the machine.
#
# Redaction is not the defence: ConvertTo-RedactedLogString masks credentials, tokens and result data,
# not statement text or identifiers taken from a query.
#
# The sibling functions named alongside it in the issue - Set-EditorValue and Set-EditorBackground -
# turned out to take NO parameters, so their preambles trace an empty set and leak nothing. Only this
# one carried the payload. Asserted below so that stays true.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Push-ToEditor.ps1")

    class RecordingTracer {
        static [System.Collections.Generic.List[string]]$Line = [System.Collections.Generic.List[string]]::new()
        static [void] WriteLine([string]$Message) {
            [RecordingTracer]::Line.Add($Message)
        }
    }

    $Script:Tracer = [RecordingTracer]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    # The push itself is not under test here; the trace line written before it is.
    $script:Pushed = [System.Collections.Generic.List[string]]::new()

    function Invoke-ExecuteScriptAsync {
        param($ScriptToExecute, $OnCompletedScriptBlock)
        $script:Pushed.Add([string]$ScriptToExecute)
    }

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
}

Describe 'Push-ToEditor tracing' -Tag 'Unit' {

    BeforeEach {
        [RecordingTracer]::Line.Clear()
        $script:Pushed.Clear()
    }

    It 'Should trace the call at all, so the assertions below are not passing on an empty trace' {
        Push-ToEditor -ScriptToExecute "window.setTheme('dark');"

        @([RecordingTracer]::Line).Count | Should -Be 1
        [RecordingTracer]::Line[0] | Should -Match 'Push-ToEditor'
    }

    It 'Should still push the payload to the editor' {
        # The fix is about the trace, not about the push. If this broke, opening a query would stop
        # loading it into the editor.
        $Script = "window.setEditorValue('SELECT 1');"

        Push-ToEditor -ScriptToExecute $Script

        @($script:Pushed).Count | Should -Be 1
        $script:Pushed[0] | Should -Be $Script
    }

    It 'Should record the payload length rather than the payload' {
        $Script = "window.setTheme('dark');"

        Push-ToEditor -ScriptToExecute $Script

        [RecordingTracer]::Line[0] | Should -Match ("<{0} characters>" -f $Script.Length)
    }

    It 'Should never write the query text of a setEditorValue push into the trace' {
        # The exact shape Set-EditorValue produces: the saved query interpolated into the script.
        $Query = "SELECT Zqx7Confidential FROM dbo.Zqx7SecretTable WHERE Name = 'Zqx7Person'"
        $Script = "window.setEditorValue('{0}');" -f $Query

        Push-ToEditor -ScriptToExecute $Script

        [RecordingTracer]::Line[0] | Should -Not -Match 'Zqx7'
        [RecordingTracer]::Line[0] | Should -Not -Match 'SELECT'
    }

    It 'Should not trace a payload written as a literal at the call site' {
        # The case that makes the guarantee unconditional rather than dependent on call-site style:
        # the preamble also wrote $MyInvocation.Statement, the SOURCE TEXT of the calling statement.
        Push-ToEditor -ScriptToExecute "window.setEditorValue('SELECT * FROM dbo.Zqx7SecretTable');"

        [RecordingTracer]::Line[0] | Should -Not -Match 'Zqx7'
        [RecordingTracer]::Line[0] | Should -Not -Match 'SELECT'
    }

    It 'Should still name the caller and the line, which is what the statement text was read for' {
        Push-ToEditor -ScriptToExecute "window.setTheme('dark');"

        [RecordingTracer]::Line[0] | Should -Match 'Caller: PushToEditorTracing\.Tests\.ps1\(\d+\)'
    }

    It 'Should not hand the raw payload to ConvertTo-RedactedLogString at all' {
        # Redaction does not mask identifiers, so the payload must never be given to it in the first
        # place.
        $Source = Get-Content -Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "src\Lib\Functions\Private\Push-ToEditor.ps1") -Raw

        $Source | Should -Not -Match 'ConvertTo-RedactedLogString -InputObject \$PSBoundParameters'
    }
}

Describe 'The editor-push functions that take no parameters' -Tag 'Unit' {

    # Named in issue #111 alongside Push-ToEditor, and checked rather than assumed: both declare an
    # empty param block, so their preambles trace an empty set and there is nothing to leak. If either
    # ever gains a parameter carrying editor content, this fails and says so.
    It 'Should keep <Function> parameterless, or trace by shape if that changes' -ForEach @(
        @{ Function = 'Set-EditorValue' }
        @{ Function = 'Set-EditorBackground' }
    ) {
        $Path = Join-Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "src\Lib\Functions\Private\$Function.ps1"
        $Source = Get-Content -Path $Path -Raw

        $Parameterless = $Source -match '(?s)function\s+' + [regex]::Escape($Function) + '\s*\{.*?param\s*\(\s*\)'
        $ShapeTraced = $Source -notmatch 'ConvertTo-RedactedLogString -InputObject \$PSBoundParameters'

        ($Parameterless -or $ShapeTraced) | Should -BeTrue -Because "$Function must not trace editor content"
    }
}
