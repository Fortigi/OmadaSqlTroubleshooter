#Requires -Version 7.0
# Tests for the T-SQL syntax pass of issue #61 - the first of the two validation passes described
# there. The schema pass (Get-SqlSchemaDiagnostic) is NOT delivered by this change and has no tests
# here.
#
# The parse assertions run against the real, pinned ScriptDom assembly rather than a stand-in,
# because the whole point of the dependency is that it produces SQL Server's own wording. A fake
# parser would let the tests agree with a message the server never sends. The assembly is resolved
# from the module's own Bin folder when it is already installed there, and downloaded from the
# pinned URL - and verified against the pinned SHA-256 - otherwise.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Get-SqlParserType.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlDiagnosticEndColumn.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlSyntaxDiagnostic.ps1")
    . (Join-Path $PrivatePath -ChildPath "ConvertTo-EditorDiagnosticScript.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SqlSyntaxWarningMessage.ps1")

    # Every log line the function under test emits is captured rather than written, so the redaction
    # assertions further down can look at exactly what would have reached the application log.
    $script:LoggedMessage = [System.Collections.Generic.List[object]]::new()

    function Write-LogOutput {
        param(
            [Parameter(ValueFromPipeline = $true)]$Message,
            [string]$LogType = "INFO",
            $ErrorObject,
            [switch]$SkipDialog
        )
        process {
            $script:LoggedMessage.Add([PSCustomObject]@{ Message = [string]$Message; LogType = $LogType })
        }
    }

    function Get-ScriptDomAssemblyPath {
        <#
            Resolves a ScriptDom assembly to test against. Prefers a copy the module has already
            installed on this machine; otherwise downloads the pinned package into a version-stamped
            cache folder and verifies the bytes against the pinned SHA-256 before using them - the
            same guarantee Invoke-DownloadFile gives at run time.
        #>
        $Lock = Import-PowerShellDataFile -Path (Join-Path $ParentPath -ChildPath "src\DependencyLock.psd1")
        $Artifact = @($Lock.Artifacts | Where-Object { $_.Id -eq "Microsoft.SqlServer.TransactSql.ScriptDom" })[0]
        if ($null -eq $Artifact) {
            return $null
        }

        $Installed = Join-Path ([System.Environment]::GetFolderPath("LocalApplicationData")) "OmadaSqlTroubleshooter\Bin\Microsoft.SqlServer.TransactSql.ScriptDom.dll"
        if (Test-Path $Installed -PathType Leaf) {
            return $Installed
        }

        $CacheRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("OmadaSqlTroubleshooter.ScriptDom.{0}" -f $Artifact.Version)
        $Cached = Join-Path $CacheRoot "Microsoft.SqlServer.TransactSql.ScriptDom.dll"
        if (Test-Path $Cached -PathType Leaf) {
            return $Cached
        }

        try {
            New-Item -Path $CacheRoot -ItemType Directory -Force | Out-Null
            $Package = Join-Path $CacheRoot "package.zip"
            Invoke-WebRequest -Uri $Artifact.Url -OutFile $Package

            $ActualHash = (Get-FileHash -Path $Package -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($ActualHash -ne $Artifact.Sha256) {
                Remove-Item -Path $Package -Force -ErrorAction SilentlyContinue
                return $null
            }

            $Expanded = Join-Path $CacheRoot "expanded"
            Expand-Archive -Path $Package -DestinationPath $Expanded -Force
            $Source = Get-ChildItem -Path $Expanded -Filter "Microsoft.SqlServer.TransactSql.ScriptDom.dll" -Recurse |
                Where-Object { $_.Directory.Name -eq "net8.0" } |
                Select-Object -First 1
            if ($null -eq $Source) {
                return $null
            }

            Copy-Item -Path $Source.FullName -Destination $Cached -Force
            Remove-Item -Path $Expanded -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $Package -Force -ErrorAction SilentlyContinue
            return $Cached
        }
        catch {
            return $null
        }
    }

    $script:ScriptDomPath = Get-ScriptDomAssemblyPath
    if ($null -ne $script:ScriptDomPath) {
        [void][Reflection.Assembly]::LoadFrom($script:ScriptDomPath)
    }

    # Once loaded, an assembly cannot be unloaded from a PowerShell session, so the "ScriptDom is
    # missing" case is exercised by making the resolver report nothing rather than by unloading
    # anything. Get-SqlSyntaxDiagnostic asks Get-SqlParserType and has no other route to a parser,
    # so this is the whole of the missing-assembly path.
    function Use-MissingScriptDom {
        param([scriptblock]$Body)

        $Original = ${function:Get-SqlParserType}
        try {
            Set-Item -Path "function:Get-SqlParserType" -Value { param($ParserVersion) return $null }
            & $Body
        }
        finally {
            Set-Item -Path "function:Get-SqlParserType" -Value $Original
        }
    }
}

Describe 'Get-SqlSyntaxDiagnostic' -Tag 'Unit' {

    BeforeEach {
        $script:LoggedMessage.Clear()
    }

    Context 'When the ScriptDom assembly is unavailable' {
        # Acceptance criterion 6: with the parser missing the application behaves exactly as before,
        # which starts with this function refusing to throw.
        It 'Should report Unavailable instead of throwing' {
            Use-MissingScriptDom {
                $Result = Get-SqlSyntaxDiagnostic -SqlText "SELECT a, FROM dbo.Person"
                $Result.Status | Should -Be "Unavailable"
            }
        }

        It 'Should return no diagnostics and no parser version' {
            Use-MissingScriptDom {
                $Result = Get-SqlSyntaxDiagnostic -SqlText "SELECT a, FROM dbo.Person"
                @($Result.Diagnostic).Count | Should -Be 0
                $Result.ParserVersion | Should -BeNullOrEmpty
            }
        }

        It 'Should not throw for a valid script either' {
            Use-MissingScriptDom {
                { Get-SqlSyntaxDiagnostic -SqlText "SELECT 1" } | Should -Not -Throw
            }
        }
    }

    Context 'When the ScriptDom assembly is available' {
        BeforeEach {
            if ($null -eq $script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
            }
        }

        It 'Should report a parse error with a line, a column and the parser message' {
            # Acceptance criterion 1. NOTE: ScriptDom - and SQL Server - report this query as
            # "Incorrect syntax near 'FROM'." at the FROM keyword, not "Incorrect syntax near ','."
            # at the comma. The parser reports the token at which the statement became
            # unparseable, which is the keyword, not the trailing comma that made it so. Asserted
            # here as the parser actually behaves; see the pull request for the discrepancy with
            # the wording in the issue.
            $Result = Get-SqlSyntaxDiagnostic -SqlText "SELECT a, FROM dbo.Person"

            $Result.Status | Should -Be "Ok"
            @($Result.Diagnostic).Count | Should -Be 1

            $Diagnostic = @($Result.Diagnostic)[0]
            $Diagnostic.Line | Should -Be 1
            $Diagnostic.Column | Should -Be 11
            $Diagnostic.Message | Should -Be "Incorrect syntax near 'FROM'."
            $Diagnostic.Severity | Should -Be "Error"
            $Diagnostic.Source | Should -Be "T-SQL syntax"
        }

        It 'Should place the marker range over the offending token' {
            $Result = Get-SqlSyntaxDiagnostic -SqlText "SELECT a, FROM dbo.Person"
            $Diagnostic = @($Result.Diagnostic)[0]

            $Diagnostic.EndLine | Should -Be $Diagnostic.Line
            $Diagnostic.EndColumn | Should -Be 15 -Because "'FROM' is four characters wide, so the squiggle covers it"
        }

        It 'Should report the line a later error is actually on' {
            $Result = Get-SqlSyntaxDiagnostic -SqlText "SELECT 1;`r`nSELECT b, FROM dbo.Person"
            @($Result.Diagnostic)[0].Line | Should -Be 2
        }

        It 'Should return no diagnostics for a valid script' {
            $Result = Get-SqlSyntaxDiagnostic -SqlText "SELECT TOP 10 p.Id FROM dbo.Person AS p WHERE p.Deleted = 0 ORDER BY p.Id DESC;"

            $Result.Status | Should -Be "Ok"
            @($Result.Diagnostic).Count | Should -Be 0
        }

        It 'Should return no diagnostics for <Label> input' -ForEach @(
            @{ Label = 'empty'; Text = '' }
            @{ Label = 'whitespace-only'; Text = "   `r`n`t  " }
            @{ Label = 'null'; Text = $null }
        ) {
            # An empty editor is not a syntax error.
            $Result = Get-SqlSyntaxDiagnostic -SqlText $Text

            $Result.Status | Should -Be "Ok"
            @($Result.Diagnostic).Count | Should -Be 0
        }

        It 'Should default to the newest parser the assembly ships' {
            # Open question 4 in the issue. Discovered by reflection, never hard-coded, so bumping
            # the pinned package picks up the newer grammar without a source change.
            $Newest = (Get-SqlParserType).Name
            $Newest | Should -Match '^TSql\d+Parser$'

            $Result = Get-SqlSyntaxDiagnostic -SqlText "SELECT 1"
            $Result.ParserVersion | Should -Be $Newest
        }

        It 'Should honour an explicitly requested parser version' {
            $Result = Get-SqlSyntaxDiagnostic -SqlText "SELECT 1" -ParserVersion "TSql130Parser"
            $Result.ParserVersion | Should -Be "TSql130Parser"
        }

        It 'Should report Unavailable for a parser version the assembly does not ship' {
            $Result = Get-SqlSyntaxDiagnostic -SqlText "SELECT 1" -ParserVersion "TSql42Parser"
            $Result.Status | Should -Be "Unavailable"
        }

        It 'Should accept input from the pipeline' {
            $Result = "SELECT 1" | Get-SqlSyntaxDiagnostic
            $Result.Status | Should -Be "Ok"
        }

        It 'Should parse a realistic query well inside the debounce interval' {
            # Acceptance criterion 5, measured rather than asserted by hand-waving. The default
            # debounce is 400 ms; the budget here is deliberately far looser than the measured cost
            # (single-digit milliseconds) so it fails on a regression of an order of magnitude and
            # not on a busy build agent.
            $Query = (1..8 | ForEach-Object {
                    "SELECT TOP 100 o.Id, o.UID, o.DisplayName FROM dbo.tblDataObject AS o INNER JOIN dbo.tblIdentity AS i ON i.Id = o.Id WHERE o.Deleted = 0 ORDER BY o.CreateTime DESC;"
                }) -join "`r`n"

            $null = Get-SqlSyntaxDiagnostic -SqlText $Query

            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $Result = Get-SqlSyntaxDiagnostic -SqlText $Query
            $Stopwatch.Stop()

            @($Result.Diagnostic).Count | Should -Be 0
            $Stopwatch.Elapsed.TotalMilliseconds | Should -BeLessThan 200
        }
    }

    Context 'The existing SQL corpus in this repository' {
        BeforeEach {
            if ($null -eq $script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
            }
        }

        # Open question 4: the default parser must not flag queries this project already treats as
        # valid. Every one of these is a SQL string that appears in the test corpus or the mock
        # fixtures. "SELECT * FROM dbo.Identity", which appears in the redaction tests, is
        # deliberately NOT here: IDENTITY is a reserved word in T-SQL, so that string is genuinely
        # invalid unqualified and SQL Server rejects it too. See the pull request.
        It 'Should find no syntax error in <Label>' -ForEach @(
            @{ Label = 'SELECT 1'; Text = 'SELECT 1' }
            @{ Label = 'SELECT TOP 10 * FROM x'; Text = 'SELECT TOP 10 * FROM x' }
            @{ Label = 'SELECT 1 FROM SomeTable'; Text = 'SELECT 1 FROM SomeTable' }
            @{ Label = 'a query with a trailing line comment'; Text = 'SELECT 1 -- Bearer abcdefghijklmnop1234567890' }
            @{ Label = 'the mock history fixture query'; Text = "SELECT TOP 20 *`r`nFROM dbo.tblDataObject" }
            @{ Label = 'the mock query-object fixture'; Text = "SELECT TOP 10`n    o.Id,`n    o.UID,`n    o.Number,`n    o.DisplayName,`n    o.CreateTime,`n    o.CreatedBy,`n    o.ChangeTime,`n    o.ChangedBy`nFROM dbo.tblDataObject AS o`nWHERE o.Deleted = 0`nORDER BY o.CreateTime DESC;" }
            @{ Label = 'a bracket-quoted reserved word'; Text = 'SELECT * FROM dbo.[Identity]' }
            @{ Label = 'a CTE'; Text = 'WITH Recent AS (SELECT Id FROM dbo.Person) SELECT Id FROM Recent' }
            @{ Label = 'a temp table'; Text = 'SELECT Id INTO #Temp FROM dbo.Person; SELECT * FROM #Temp;' }
            @{ Label = 'a table variable'; Text = 'DECLARE @Rows TABLE (Id int); SELECT * FROM @Rows;' }
            @{ Label = 'CROSS APPLY over OPENJSON'; Text = "SELECT j.a FROM dbo.Person p CROSS APPLY OPENJSON(p.Payload) WITH (a int) AS j" }
            @{ Label = 'dynamic SQL'; Text = "EXEC sp_executesql N'SELECT 1'" }
        ) {
            $Result = Get-SqlSyntaxDiagnostic -SqlText $Text

            $Result.Status | Should -Be "Ok"
            @($Result.Diagnostic).Count | Should -Be 0 -Because "'$Label' is a query this project treats as valid"
        }
    }

    Context 'Logging and redaction (issue #61 section 5)' {
        BeforeEach {
            if ($null -eq $script:ScriptDomPath) {
                Set-ItResult -Inconclusive -Because "the pinned ScriptDom package could not be resolved or downloaded on this machine"
            }
        }

        # A negative criterion, so it is asserted against a script built out of tokens that could
        # not plausibly appear in the function's own output by coincidence.
        It 'Should never write the script, an identifier from it, or a parse message to the log' {
            $Secret = "Zqx7Confidential"
            $null = Get-SqlSyntaxDiagnostic -SqlText ("SELECT {0}.Column1, FROM dbo.{0} WHERE Note = 'password=hunter2'" -f $Secret)

            @($script:LoggedMessage).Count | Should -BeGreaterThan 0 -Because "the function does log a count, so an empty log would pass this test for the wrong reason"

            foreach ($Entry in $script:LoggedMessage) {
                $Entry.Message | Should -Not -Match ([regex]::Escape($Secret))
                $Entry.Message | Should -Not -Match 'SELECT'
                $Entry.Message | Should -Not -Match 'hunter2'
                $Entry.Message | Should -Not -Match 'Incorrect syntax'
            }
        }

        It 'Should log nothing above DEBUG' {
            $null = Get-SqlSyntaxDiagnostic -SqlText "SELECT a, FROM dbo.Person"

            # DEBUG and VERBOSE are the only levels a query-derived detail may reach. INFO, WARNING,
            # ERROR, FATAL and LOG are all visible at the default WARNING log level, and the log
            # window has an "Export Log File" button.
            foreach ($Entry in $script:LoggedMessage) {
                $Entry.LogType | Should -BeIn @("DEBUG", "VERBOSE", "VERBOSE2")
            }
        }

        It 'Should carry no tracer preamble that would trace the query text' {
            # The preamble every other function opens with writes
            # ConvertTo-RedactedLogString -InputObject $PSBoundParameters, and ConvertTo-RedactedLogString
            # deliberately does NOT redact query text. Here $PSBoundParameters IS the query, so the
            # preamble is omitted on purpose and this test is what stops it being "restored for
            # consistency" later.
            $Source = Get-Content -Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "src\Lib\Functions\Private\Get-SqlSyntaxDiagnostic.ps1") -Raw
            $Source | Should -Not -Match 'Tracer::WriteLine'
        }
    }
}

Describe 'ConvertTo-EditorDiagnosticScript' -Tag 'Unit' {

    # The single diagnostics channel into Monaco (issue #61 section 3). The shape asserted here is
    # the contract the schema pass will reuse unchanged, so a change to it should break these tests.

    Context 'The marker payload' {
        It 'Should call setDiagnostics with a JSON array' {
            $Script = ConvertTo-EditorDiagnosticScript -Diagnostic @(
                [PSCustomObject]@{ Line = 3; Column = 7; EndLine = 3; EndColumn = 11; Severity = "Error"; Message = "Incorrect syntax near 'FROM'."; Source = "T-SQL syntax" }
            )

            $Script | Should -BeLike "setDiagnostics(*);"
            $Script | Should -Match '^setDiagnostics\(\[\{' -Because "the argument must be an array of marker objects"

            $Payload = $Script -replace '^setDiagnostics\(', '' -replace '\);$', '' | ConvertFrom-Json
            @($Payload).Count | Should -Be 1
        }

        It 'Should emit every field the editor seam reads, in camelCase' {
            $Script = ConvertTo-EditorDiagnosticScript -Diagnostic @(
                [PSCustomObject]@{ Line = 3; Column = 7; EndLine = 4; EndColumn = 11; Severity = "Error"; Message = "boom"; Source = "T-SQL syntax" }
            )
            $Marker = @(($Script -replace '^setDiagnostics\(', '' -replace '\);$', '' | ConvertFrom-Json))[0]

            $Marker.line | Should -Be 3
            $Marker.column | Should -Be 7
            $Marker.endLine | Should -Be 4
            $Marker.endColumn | Should -Be 11
            $Marker.severity | Should -Be "Error"
            $Marker.message | Should -Be "boom"
            $Marker.source | Should -Be "T-SQL syntax"
        }

        It 'Should round-trip <Severity>, so the schema pass can share this channel' -ForEach @(
            @{ Severity = 'Error' }
            @{ Severity = 'Warning' }
        ) {
            $Script = ConvertTo-EditorDiagnosticScript -Diagnostic @(
                [PSCustomObject]@{ Line = 1; Column = 1; EndLine = 1; EndColumn = 2; Severity = $Severity; Message = "m"; Source = "s" }
            )
            $Marker = @(($Script -replace '^setDiagnostics\(', '' -replace '\);$', '' | ConvertFrom-Json))[0]

            $Marker.severity | Should -Be $Severity
        }

        It 'Should emit a flat JSON array for <Count> diagnostic(s)' -ForEach @(
            @{ Count = 0 }
            @{ Count = 1 }
            @{ Count = 3 }
        ) {
            # Asserted on the literal text rather than through ConvertFrom-Json: PowerShell
            # flattens nested arrays on the way out of ConvertFrom-Json, so a "[[{...}]]" payload -
            # which JavaScript would read as a list of one list, and which setModelMarkers would
            # reject - survives every round-trip assertion unnoticed. It did.
            # Not "1..$Count": the range operator counts DOWN when the end is below the start, so
            # 1..0 yields two elements rather than none.
            $Diagnostic = @(for ($Index = 1; $Index -le $Count; $Index++) {
                    [PSCustomObject]@{ Line = $Index; Column = 1; EndLine = $Index; EndColumn = 2; Severity = "Error"; Message = "m"; Source = "s" }
                })

            $Script = ConvertTo-EditorDiagnosticScript -Diagnostic $Diagnostic

            $Script | Should -Match '^setDiagnostics\(\[(\{.*\})?\]\);$' -Because "the payload must be a flat array of objects"
            ([regex]::Matches($Script, '"line":')).Count | Should -Be $Count
        }

        It 'Should clear the markers for <Label>' -ForEach @(
            @{ Label = 'an empty collection'; Value = @() }
            @{ Label = 'a null'; Value = $null }
        ) {
            ConvertTo-EditorDiagnosticScript -Diagnostic $Value | Should -Be "setDiagnostics([]);"
        }
    }

    Context 'The Monaco side of the seam' {
        BeforeAll {
            $Script:IndexHtml = Get-Content -Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "src\Monaco\index.html") -Raw
        }

        It 'Should expose window.setDiagnostics next to the other editor seams' {
            $Script:IndexHtml | Should -Match 'window\.setDiagnostics\s*=\s*function'
            $Script:IndexHtml | Should -Match 'window\.setSchema\s*=\s*function' -Because "the diagnostics seam mirrors the schema seam"
        }

        It 'Should apply the markers with monaco.editor.setModelMarkers' {
            $Script:IndexHtml | Should -Match 'monaco\.editor\.setModelMarkers'
        }

        It 'Should map <Severity> onto a Monaco marker severity' -ForEach @(
            @{ Severity = 'error' }
            @{ Severity = 'warning' }
        ) {
            # Both severities must be mappable from the same channel, or the schema pass would need
            # its own seam - which is the thing this design exists to avoid.
            $Script:IndexHtml | Should -Match ('{0}:\s*monaco\.MarkerSeverity\.' -f $Severity)
        }

        It 'Should read the same field names the payload emits' {
            foreach ($Field in @('line', 'column', 'endLine', 'endColumn', 'severity', 'message', 'source')) {
                $Script:IndexHtml | Should -Match ('diagnostic\.{0}\b' -f $Field) -Because "the seam must read the '$Field' the payload writes"
            }
        }
    }
}

Describe 'Update-SqlSyntaxDiagnostic' -Tag 'Unit' {

    # The editor must never be left showing markers from an earlier parse of different text: a stale
    # squiggle is indistinguishable from a live one. Raised in review of PR #74.

    BeforeAll {
        . (Join-Path (Join-Path (Split-Path -Path $PSScriptRoot -Parent) "src\Lib\Functions\Private") "Update-SqlSyntaxDiagnostic.ps1")

        $script:PushedEditorScripts = [System.Collections.Generic.List[string]]::new()

        function Invoke-ExecuteScriptAsync {
            param($ScriptToExecute, $OnCompletedScriptBlock)
            $script:PushedEditorScripts.Add([string]$ScriptToExecute)
        }

        function Invoke-ExecuteScriptWithResultAsync {
            param($ScriptToExecute, $OnCompletedScriptBlock)
            throw "Update-SqlSyntaxDiagnostic must not read the editor when it was handed the text."
        }

        $script:ValidationSetting = $null
        $script:SyntaxResult = $null

        function Get-SqlValidationSetting { return $script:ValidationSetting }

        function Get-SqlSyntaxDiagnostic {
            param([string]$SqlText, [string]$ParserVersion, [string]$Source)
            return $script:SyntaxResult
        }
    }

    BeforeEach {
        $script:PushedEditorScripts.Clear()
        $script:ValidationSetting = [PSCustomObject]@{
            Enabled                 = $true
            DebounceMilliseconds    = 400
            WarnOnExecuteWithErrors = $true
            ParserVersion           = $null
        }
    }

    It 'Should push the diagnostics it found' {
        $script:SyntaxResult = [PSCustomObject]@{
            Status        = "Ok"
            ParserVersion = "TSql180Parser"
            Diagnostic    = @([PSCustomObject]@{ Line = 1; Column = 11; EndLine = 1; EndColumn = 15; Severity = "Error"; Message = "Incorrect syntax near 'FROM'."; Source = "T-SQL syntax" })
        }

        Update-SqlSyntaxDiagnostic -SqlText "SELECT a, FROM dbo.Person"

        @($script:PushedEditorScripts).Count | Should -Be 1
        $script:PushedEditorScripts[0] | Should -Match 'setDiagnostics\(\[\{'
    }

    It 'Should clear the markers when the script parses clean' {
        $script:SyntaxResult = [PSCustomObject]@{ Status = "Ok"; ParserVersion = "TSql180Parser"; Diagnostic = @() }

        Update-SqlSyntaxDiagnostic -SqlText "SELECT 1"

        $script:PushedEditorScripts[0] | Should -Be "setDiagnostics([]);"
    }

    It 'Should clear the markers when the parse could not run, rather than leaving stale ones' {
        # E.g. a configured SqlParserVersion the assembly does not ship. Nothing was checked, so
        # nothing may keep claiming to be wrong.
        $script:SyntaxResult = [PSCustomObject]@{ Status = "Unavailable"; ParserVersion = $null; Diagnostic = @() }

        Update-SqlSyntaxDiagnostic -SqlText "SELECT a, FROM dbo.Person"

        @($script:PushedEditorScripts).Count | Should -Be 1
        $script:PushedEditorScripts[0] | Should -Be "setDiagnostics([]);"
    }

    It 'Should push nothing at all when the pass is switched off' {
        # Distinct from "could not parse": the user asked for no validation, so the editor is left
        # exactly as it is and no script is sent to it.
        $script:ValidationSetting.Enabled = $false
        $script:SyntaxResult = [PSCustomObject]@{ Status = "Ok"; ParserVersion = "TSql180Parser"; Diagnostic = @() }

        Update-SqlSyntaxDiagnostic -SqlText "SELECT a, FROM dbo.Person"

        @($script:PushedEditorScripts).Count | Should -Be 0
    }
}

Describe 'Get-SqlSyntaxWarningMessage' -Tag 'Unit' {

    # Acceptance criterion 4: syntax errors prompt once and can be overruled.

    It 'Should return nothing when there is nothing to confirm' {
        Get-SqlSyntaxWarningMessage -Diagnostic @() | Should -BeNullOrEmpty
        Get-SqlSyntaxWarningMessage -Diagnostic $null | Should -BeNullOrEmpty
    }

    It 'Should count a single error and point at it' {
        $Message = Get-SqlSyntaxWarningMessage -Diagnostic @(
            [PSCustomObject]@{ Line = 2; Column = 9; Severity = "Error"; Message = "Incorrect syntax near 'FROM'."; Source = "T-SQL syntax" }
        )

        $Message | Should -Match '1 syntax error'
        $Message | Should -Match 'line 2'
        $Message | Should -Match 'column 9'
    }

    It 'Should point at the first error when there are several' {
        $Message = Get-SqlSyntaxWarningMessage -Diagnostic @(
            [PSCustomObject]@{ Line = 7; Column = 2; Severity = "Error"; Message = "b"; Source = "T-SQL syntax" }
            [PSCustomObject]@{ Line = 3; Column = 5; Severity = "Error"; Message = "a"; Source = "T-SQL syntax" }
        )

        $Message | Should -Match '2 syntax errors'
        $Message | Should -Match 'line 3'
        $Message | Should -Match 'column 5'
    }

    It 'Should offer to execute rather than announce a refusal' {
        $Message = Get-SqlSyntaxWarningMessage -Diagnostic @(
            [PSCustomObject]@{ Line = 1; Column = 1; Severity = "Error"; Message = "x"; Source = "T-SQL syntax" }
        )

        $Message | Should -Match 'Execute the query\?'
        $Message | Should -Match 'can disagree with the server'
    }

    It 'Should not repeat the parser message, which quotes the script' {
        # The dialog text is passed to Open-ChoiceForm, which traces its bound parameters. The
        # squiggle in the editor already carries the message.
        $Message = Get-SqlSyntaxWarningMessage -Diagnostic @(
            [PSCustomObject]@{ Line = 1; Column = 1; Severity = "Error"; Message = "Incorrect syntax near 'SecretTableName'."; Source = "T-SQL syntax" }
        )

        $Message | Should -Not -Match 'SecretTableName'
        $Message | Should -Not -Match 'Incorrect syntax'
    }
}
