#Requires -Version 7.0
# The view lookup as one background job (issue #90, slice A).
#
# Get-SqlTroubleShooterView makes two dependent GetPagingData round-trips - the second needs the view
# id the first returns - and Update-DataConnectionList follows them with a third. All three run as
# ONE worker job so there is one completion rather than three, which is the number of places
# Set-ActiveTabContext can repoint underneath the work.
#
# Each case asserts the ORDER and SHAPE of the requests, using a recording transport, so a change to
# the sequencing fails here rather than on someone's tenant.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $script:PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $script:PrivatePath -ChildPath "New-OmadaPagingRequest.ps1")
    . (Join-Path $script:PrivatePath -ChildPath "Invoke-OmadaViewLookupPipeline.ps1")

    $script:Calls = [System.Collections.Generic.List[object]]::new()
    $script:Responses = @{}
    $script:Failures = @{}

    function script:Get-CallKey {
        param($Method, $Uri, $Body)
        if ($Uri -like "*dataobjdlg.aspx*") { return "page" }
        if ($Body.dataType -eq "Views") { return "find-view" }
        if ($Body.dataType -eq "DataObjects") { return "view-rows" }
        return "unknown"
    }

    function Invoke-OmadaRequestCore {
        param([hashtable]$Parameters)
        $Key = Get-CallKey -Method $Parameters.Method -Uri $Parameters.Uri -Body $Parameters.Body
        $script:Calls.Add([pscustomobject]@{ Key = $Key; Method = $Parameters.Method; Uri = $Parameters.Uri; Body = $Parameters.Body; SessionKey = $Parameters.SessionKey })

        if ($script:Failures.ContainsKey($Key)) {
            return @{ Result = $null; ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new($script:Failures[$Key]), "ViewLookupTestFailure",
                    [System.Management.Automation.ErrorCategory]::ConnectionError, $null) }
        }
        if ($script:Responses.ContainsKey($Key)) {
            return @{ Result = $script:Responses[$Key]; ErrorRecord = $null }
        }
        return @{ Result = $null; ErrorRecord = $null }
    }

    function script:New-ViewResponse {
        param([object[]]$Views)
        return [pscustomobject]@{ d = [pscustomobject]@{ Records = @($Views).Count; Rows = $Views } }
    }

    function script:Reset-Transport {
        param([switch]$NoView, [switch]$NoRows)

        $script:Calls.Clear()
        $script:Failures = @{}
        $script:Responses = @{}

        if (-not $NoView) {
            $script:Responses["find-view"] = New-ViewResponse -Views @(
                [pscustomobject]@{ Id = 7; Name = "Some other view" },
                [pscustomobject]@{ Id = 42; Name = "SQL Troubleshooting" }
            )
        }
        else {
            $script:Responses["find-view"] = New-ViewResponse -Views @()
        }

        $script:Rows = if ($NoRows) { @() } else { @([pscustomobject]@{ Id = 900; C_SQLQUERYDOID = "abc-123" }) }
        $script:Responses["view-rows"] = [pscustomobject]@{ d = [pscustomobject]@{ Rows = $script:Rows } }
        $script:Responses["page"] = "<html>the data connection page</html>"
    }

    # The code, without its comments. A purity scan over raw source is defeated by its own
    # documentation: this function's help explains WHY it may not read $Script: state, and a naive
    # match then fails on the explanation rather than on a violation. Tokenizing drops comments -
    # including the comment-based help block, which is one Comment token.
    function script:Get-CodeOnly {
        param([string]$Path)
        $Private:Tokens = $null
        $Private:Errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Private:Tokens, [ref]$Private:Errors)
        return (($Private:Tokens | Where-Object { $_.Kind -ne "Comment" }).Text -join " ")
    }

    function script:New-Context {
        param([switch]$IncludeDataObjectHtml)
        return @{
            BaseUrl               = "https://tenant.omada.cloud"
            Parameters            = @{ SessionKey = "tab-1"; Uri = "stale"; Method = "STALE" }
            IncludeDataObjectHtml = [bool]$IncludeDataObjectHtml
            SqlQueryDoIdField     = "C_SQLQUERYDOID"
        }
    }
}

Describe "Invoke-OmadaViewLookupPipeline" {
    BeforeEach { Reset-Transport }

    Context "The happy path" {
        It "looks the view up, then fetches its rows, in that order" {
            $null = Invoke-OmadaViewLookupPipeline -Context (New-Context)

            $script:Calls.Key | Should -Be @("find-view", "view-rows")
        }

        It "returns the rows" {
            $Private:Outcome = Invoke-OmadaViewLookupPipeline -Context (New-Context)

            @($Private:Outcome.Rows).Count | Should -Be 1
            $Private:Outcome.Rows[0].Id | Should -Be 900
        }

        It "takes one view even when the tenant holds two of that name" {
            # Without -First 1 the match is an array, and "{0}" -f an array formats as
            # System.Object[] - an invalid viewId and pageQueryString. The inline path in
            # Get-SqlTroubleShooterView must agree; a source assertion below keeps it honest.
            $script:Responses["find-view"] = New-ViewResponse -Views @(
                [pscustomobject]@{ Id = 42; Name = "SQL Troubleshooting" },
                [pscustomobject]@{ Id = 43; Name = "SQL Troubleshooting" }
            )

            $null = Invoke-OmadaViewLookupPipeline -Context (New-Context)

            ($script:Calls | Where-Object { $_.Key -eq "view-rows" }).Body.dataTypeArgs.viewId | Should -Be "42"
        }

        It "picks the view by exact name, not by the search match" {
            # The search is a contains-match, so the response legitimately holds other views. Taking
            # the first row would pass on any fixture where the wanted view happens to come first.
            $Private:Outcome = Invoke-OmadaViewLookupPipeline -Context (New-Context)

            $Private:Outcome.ViewId | Should -Be 42
            $Private:Outcome.ViewFound | Should -BeTrue
        }

        It "asks the second request for the view the first one found" {
            $null = Invoke-OmadaViewLookupPipeline -Context (New-Context)

            $Private:RowCall = $script:Calls | Where-Object { $_.Key -eq "view-rows" }
            $Private:RowCall.Body.dataTypeArgs.viewId | Should -Be "42"
            $Private:RowCall.Body.dataTypeArgs.pageQueryString | Should -Be "https://tenant.omada.cloud/dataobjlst.aspx?view=42"
        }

        It "counts both steps as completed" {
            (Invoke-OmadaViewLookupPipeline -Context (New-Context)).CompletedSteps | Should -Be 2
        }

        It "carries the session's transport settings into every step" {
            # The splat is cloned per step with only Uri, Method and Body replaced. Losing SessionKey
            # would send the worker's requests to the wrong authenticated session.
            $null = Invoke-OmadaViewLookupPipeline -Context (New-Context)

            @($script:Calls | Where-Object { $_.SessionKey -ne "tab-1" }).Count | Should -Be 0
        }

        It "overwrites the stale Uri and Method left on the splat" {
            $null = Invoke-OmadaViewLookupPipeline -Context (New-Context)

            @($script:Calls | Where-Object { $_.Uri -eq "stale" -or $_.Method -eq "STALE" }).Count | Should -Be 0
        }
    }

    Context "The optional data connection page" {
        It "fetches it as a third step of the same job" {
            # The whole point of the slice: three round-trips, one completion.
            $null = Invoke-OmadaViewLookupPipeline -Context (New-Context -IncludeDataObjectHtml)

            $script:Calls.Key | Should -Be @("find-view", "view-rows", "page")
        }

        It "opens the first row's data object" {
            $null = Invoke-OmadaViewLookupPipeline -Context (New-Context -IncludeDataObjectHtml)

            ($script:Calls | Where-Object { $_.Key -eq "page" }).Uri | Should -Be "https://tenant.omada.cloud/dataobjdlg.aspx?DOID=abc-123"
        }

        It "returns the page" {
            (Invoke-OmadaViewLookupPipeline -Context (New-Context -IncludeDataObjectHtml)).DataObjectHtml | Should -Be "<html>the data connection page</html>"
        }

        It "does not fetch it when the caller did not ask for it" {
            $null = Invoke-OmadaViewLookupPipeline -Context (New-Context)

            @($script:Calls | Where-Object { $_.Key -eq "page" }).Count | Should -Be 0
        }

        It "reports an empty view as an empty array, never as null" {
            # A jqGrid payload for a view with nothing in it has a null .d.Rows, and @($null).Count is
            # 1 - so a caller asking "did I get rows?" the obvious way was told yes. Normalising here
            # means no caller has to know that.
            Reset-Transport
            $script:Responses["view-rows"] = [pscustomobject]@{ d = [pscustomobject]@{ Rows = $null } }

            $Private:Outcome = Invoke-OmadaViewLookupPipeline -Context (New-Context)

            # Compared, not piped: Should unrolls the pipeline, so an empty array arrives as nothing
            # and the assertion would be about $null either way.
            ($null -eq $Private:Outcome.Rows) | Should -BeFalse
            @($Private:Outcome.Rows).Count | Should -Be 0
        }

        It "does not fetch it when the view returned no rows" {
            Reset-Transport -NoRows

            $Private:Outcome = Invoke-OmadaViewLookupPipeline -Context (New-Context -IncludeDataObjectHtml)

            @($script:Calls | Where-Object { $_.Key -eq "page" }).Count | Should -Be 0
            $Private:Outcome.ErrorRecord | Should -BeNullOrEmpty
        }
    }

    Context "When the view does not exist" {
        BeforeEach { Reset-Transport -NoView }

        It "stops after the lookup" {
            $null = Invoke-OmadaViewLookupPipeline -Context (New-Context)

            $script:Calls.Key | Should -Be @("find-view")
        }

        It "reports it as an answer, not as a failure" {
            # Reporting it through ErrorRecord would send the caller down the retry-on-the-UI-thread
            # path, which would ask the same question again and get the same answer.
            $Private:Outcome = Invoke-OmadaViewLookupPipeline -Context (New-Context)

            $Private:Outcome.ErrorRecord | Should -BeNullOrEmpty
            $Private:Outcome.ViewFound | Should -BeFalse
            $Private:Outcome.Rows | Should -BeNullOrEmpty
        }
    }

    Context "When a step fails" {
        It "stops at the failing step and names it" {
            Reset-Transport
            $script:Failures["find-view"] = "the tenant said no"

            $Private:Outcome = Invoke-OmadaViewLookupPipeline -Context (New-Context)

            $script:Calls.Key | Should -Be @("find-view")
            $Private:Outcome.FailedStep | Should -Be "FindView"
            $Private:Outcome.ErrorRecord.Exception.Message | Should -Be "the tenant said no"
        }

        It "reports how many steps had already succeeded" {
            # This is what tells the caller "could not reach the tenant" from "the tenant refused
            # something", and only the first is safe to retry.
            Reset-Transport
            $script:Failures["view-rows"] = "gone"

            $Private:Outcome = Invoke-OmadaViewLookupPipeline -Context (New-Context)

            $Private:Outcome.FailedStep | Should -Be "FetchViewRows"
            $Private:Outcome.CompletedSteps | Should -Be 1
        }

        It "names the page step when that is the one that failed" {
            Reset-Transport
            $script:Failures["page"] = "no page"

            $Private:Outcome = Invoke-OmadaViewLookupPipeline -Context (New-Context -IncludeDataObjectHtml)

            $Private:Outcome.FailedStep | Should -Be "FetchDataConnectionPage"
            $Private:Outcome.CompletedSteps | Should -Be 2
        }

        It "returns an outcome rather than throwing when something unexpected happens" {
            # A throw from a worker surfaces as a job that died, which the UI thread cannot classify -
            # it has no ErrorRecord to run through Resolve-OmadaRequestFailure and no step trace.
            #
            # A string where the splat should be: .Clone() does not exist on it, so this throws from
            # inside the step helper rather than at the boundary. (Passing $null instead would fail
            # parameter binding before the function is entered, which tests PowerShell, not this.)
            Reset-Transport
            # script:, not Private: - the Should -Not -Throw body runs in a child scope, where a
            # $Private: variable does not resolve and the call would fail on a null argument instead
            # of on the thing being tested.
            $script:Broken = New-Context
            $script:Broken.Parameters = "not a hashtable"

            { $script:Unexpected = Invoke-OmadaViewLookupPipeline -Context $script:Broken } | Should -Not -Throw
            $script:Unexpected.ErrorRecord | Should -Not -BeNullOrEmpty
            $script:Unexpected.FailedStep | Should -Be "ViewLookup"
        }
    }

    Context "What it records for the UI thread" {
        It "logs each request's URL, for a log that reads as it always did" {
            $Private:Outcome = Invoke-OmadaViewLookupPipeline -Context (New-Context)

            @($Private:Outcome.Log | Where-Object { $_.Text -like "QueryUrl:*" }).Count | Should -Be 2
        }

        It "hands the body over to be redacted rather than writing it out" {
            # ConvertTo-RedactedLogString is a UI-thread function. The worker records WHAT to log and
            # the UI thread decides how much of it may be written down.
            $Private:Outcome = Invoke-OmadaViewLookupPipeline -Context (New-Context)

            @($Private:Outcome.Log | Where-Object { $null -ne $_.Redact }).Count | Should -BeGreaterThan 0
        }

        It "traces the steps it ran" {
            $Private:Outcome = Invoke-OmadaViewLookupPipeline -Context (New-Context -IncludeDataObjectHtml)

            $Private:Outcome.Steps.Name | Should -Be @("FindView", "FetchViewRows", "FetchDataConnectionPage")
        }
    }

    It "does not disagree with the inline path about an empty row set either" {
        # Both paths normalise .d.Rows to an array, because a null one counted as a single row and
        # every caller downstream believed it.
        $Private:Inline = Get-Content -Path (Join-Path $script:PrivatePath "Get-SqlTroubleShooterView.ps1") -Raw

        $Private:Inline | Should -Match '@\(\$Private:Result\.d\.Rows \| Where-Object \{ \$null -ne \$_ \}\)'
    }

    It "does not disagree with the inline path about picking one view" {
        # The two paths build the same requests by construction (New-OmadaPagingRequest); this is the
        # one decision made OUTSIDE the builder, so it is the one place they can still drift.
        $Private:Inline = Get-Content -Path (Join-Path $script:PrivatePath "Get-SqlTroubleShooterView.ps1") -Raw

        $Private:Inline | Should -Match 'Where-Object \{ \$_\.Name -eq "SQL Troubleshooting" \} \| Select-Object -First 1'
    }

    It "is runspace-safe - no script state, no logging, no WPF" {
        # It runs in a worker runspace, where none of that exists. A single $Script: read here is a
        # CommandNotFoundException or a null in a background job, found on a tenant rather than here.
        $Private:Code = Get-CodeOnly -Path (Join-Path $script:PrivatePath "Invoke-OmadaViewLookupPipeline.ps1")

        $Private:Code | Should -Not -Match '\$Script:'
        $Private:Code | Should -Not -Match 'Write-LogOutput'
        $Private:Code | Should -Not -Match 'System\.Windows'
    }
}
