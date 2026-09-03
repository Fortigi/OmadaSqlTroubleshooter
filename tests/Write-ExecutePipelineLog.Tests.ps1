#Requires -Version 7.0
# Moving the execute chain into a worker cost this application most of its diagnostic value: the URL,
# the body, the parameter set and the response used to be in the log for every execute, and after
# C1-5 none of them were, because a worker runspace has no log file. These tests are about getting
# that back without moving redaction off the UI thread.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Write-ExecutePipelineLog.ps1")

    $script:LogMessages = [System.Collections.Generic.List[object]]::new()
    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$InputObject,
            [string]$LogType,
            $ErrorObject,
            [switch]$SkipDialog
        )
        process { $script:LogMessages.Add([pscustomobject]@{ LogType = $LogType; Message = [string]$InputObject; SkipDialog = [bool]$SkipDialog }) }
    }

    $script:RedactCalls = [System.Collections.Generic.List[object]]::new()
    function ConvertTo-RedactedLogString {
        param($InputObject, [switch]$ShapeOnly, $MaxDepth)
        $script:RedactCalls.Add([pscustomobject]@{ InputObject = $InputObject; ShapeOnly = [bool]$ShapeOnly })
        if ($ShapeOnly) { return "<shape>" }
        return "<redacted:$($InputObject.Marker)>"
    }
}

Describe "Write-ExecutePipelineLog" {
    BeforeEach {
        $script:LogMessages.Clear()
        $script:RedactCalls.Clear()
    }

    It "replays finished lines at the level the worker chose, in order" {
        Write-ExecutePipelineLog -Log @(
            @{ Level = "INFO"; Text = "Retrieve query 1234" }
            @{ Level = "DEBUG"; Text = "Save query" }
        )

        @($script:LogMessages).Count | Should -Be 2
        $script:LogMessages[0].LogType | Should -Be "INFO"
        $script:LogMessages[0].Message | Should -Be "Retrieve query 1234"
        $script:LogMessages[1].LogType | Should -Be "DEBUG"
    }

    It "redacts objects here rather than in the worker" {
        # The reason this function exists at all rather than the worker formatting its own strings:
        # ConvertTo-RedactedLogString is a UI-thread function and stays the single place that decides
        # what may be written down.
        Write-ExecutePipelineLog -Log @(
            @{ Level = "VERBOSE"; Format = "Parameters: {0}"; Redact = @{ Marker = "params" } }
        )

        $script:LogMessages[0].Message | Should -Be "Parameters: <redacted:params>"
        @($script:RedactCalls).Count | Should -Be 1
        $script:RedactCalls[0].ShapeOnly | Should -BeFalse
    }

    It "honours ShapeOnly, so a request body is logged as a shape and not as content" {
        Write-ExecutePipelineLog -Log @(
            @{ Level = "VERBOSE"; Format = "Body: {0}"; Redact = @{ Marker = "body" }; ShapeOnly = $true }
        )

        $script:RedactCalls[0].ShapeOnly | Should -BeTrue
        $script:LogMessages[0].Message | Should -Be "Body: <shape>"
    }

    It "writes every entry with SkipDialog" {
        # A replay must never open a modal. A single execute records a dozen of these, and they
        # describe things that have already happened.
        Write-ExecutePipelineLog -Log @(
            @{ Level = "INFO"; Text = "one" }
            @{ Level = "DEBUG"; Text = "two" }
        )

        @($script:LogMessages | Where-Object { -not $_.SkipDialog }).Count | Should -Be 0
    }

    It "defaults an entry with no level to DEBUG" {
        Write-ExecutePipelineLog -Log @(@{ Text = "no level" })

        $script:LogMessages[0].LogType | Should -Be "DEBUG"
    }

    It "skips null and empty entries instead of logging blank lines" {
        Write-ExecutePipelineLog -Log @($null, @{ Level = "INFO"; Text = "" }, @{ Level = "INFO"; Text = "kept" })

        @($script:LogMessages).Count | Should -Be 1
        $script:LogMessages[0].Message | Should -Be "kept"
    }

    It "keeps going when one entry cannot be logged" {
        # One object that will not redact must not cost the log every entry after it.
        Mock ConvertTo-RedactedLogString { throw "cannot redact" } -ParameterFilter { $InputObject.Marker -eq "bad" }

        Write-ExecutePipelineLog -Log @(
            @{ Level = "INFO"; Text = "before" }
            @{ Level = "VERBOSE"; Format = "{0}"; Redact = @{ Marker = "bad" } }
            @{ Level = "INFO"; Text = "after" }
        )

        @($script:LogMessages.Message) | Should -Be @("before", "after")
    }

    It "accepts a null log without throwing" {
        { Write-ExecutePipelineLog -Log $null } | Should -Not -Throw
        @($script:LogMessages).Count | Should -Be 0
    }
}
