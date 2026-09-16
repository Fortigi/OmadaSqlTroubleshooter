#Requires -Version 7.0

BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $Script:WorkflowsPath = Join-Path -Path $Script:RepositoryRoot -ChildPath '.github\workflows'

    $Script:WorkflowFiles = @(Get-ChildItem -Path $Script:WorkflowsPath -Filter '*.yml' -File) +
        @(Get-ChildItem -Path $Script:WorkflowsPath -Filter '*.yaml' -File)

    # Strips a trailing YAML comment before any of the permissions matching below runs. Kept
    # deliberately simple - everything from the first `#` to end of line is dropped - rather than a
    # full quoting-aware parser, because none of these workflow files ever puts a literal `#` inside
    # a quoted scope value. Without this, "permissions: {} # do not write to anything here" would
    # fail the compliant-block check, and "contents: write # needed for tags" would slip past it.
    function Get-YamlLineWithoutComment {
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string] $Line
        )

        return ($Line -replace '#.*$', '').TrimEnd()
    }

    # YAML treats a quoted scalar and its bare equivalent identically, so "write" and 'write' and
    # write must all compare equal. Strips one matching pair of leading/trailing quotes, if present,
    # after the value has already been trimmed of surrounding whitespace.
    function Get-YamlValueWithoutQuote {
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string] $Value
        )

        return ($Value.Trim() -replace '^([''"])(.*)\1$', '$2')
    }
}

Describe 'Workflow permissions' -Tag 'Unit' {

    It 'Should find at least one workflow file to check' {
        $Script:WorkflowFiles.Count | Should -BeGreaterThan 0 -Because 'this test exists to guard .github/workflows'
    }

    Context 'Every workflow file' {

        It 'Should declare a workflow-level permissions: block' {
            # Matched at column 0 - an unindented `permissions:` key is workflow-level, unlike the
            # indented `permissions:` blocks nested under a job. Read as plain lines rather than
            # parsed as YAML, since the repository has no YAML parser dependency to add for this.
            $Missing = foreach ($File in $Script:WorkflowFiles) {
                $Lines = Get-Content -LiteralPath $File.FullName
                $TopLevelPermissions = @($Lines | Where-Object { $_ -match '^permissions:' })
                if ($TopLevelPermissions.Count -eq 0) {
                    $File.Name
                }
            }
            $Missing | Should -BeNullOrEmpty -Because "every workflow must declare an explicit least-privilege permissions block, even if it is just permissions: {}`n$($Missing -join "`n")"
        }

        It 'Should not grant a write scope at workflow level' {
            # The previous test only proves a permissions: block exists - it would still pass if
            # someone reintroduced a workflow-level "permissions: contents: write", which is exactly
            # the over-broad grant issue #140 removed. Every write scope must live on the one job
            # that needs it instead, so this test walks the workflow-level block's own lines (the
            # ones indented under `permissions:`, stopping at the next column-0 key) and fails if any
            # of them grants write.
            $Offenders = foreach ($File in $Script:WorkflowFiles) {
                $Lines = Get-Content -LiteralPath $File.FullName
                $PermissionsLineIndex = -1
                for ($LineIndex = 0; $LineIndex -lt $Lines.Count; $LineIndex++) {
                    if ($Lines[$LineIndex] -match '^permissions:') {
                        $PermissionsLineIndex = $LineIndex
                        break
                    }
                }
                if ($PermissionsLineIndex -lt 0) {
                    continue
                }

                $PermissionsLine = $Lines[$PermissionsLineIndex]
                $PermissionsLineStripped = Get-YamlLineWithoutComment -Line $PermissionsLine

                # Whatever follows `permissions:` on its own line - empty means a block mapping
                # follows on subsequent lines, handled by the indented-line scan below.
                $InlineValue = [regex]::Match($PermissionsLineStripped, '^permissions:\s*(?<Value>\S.*)$').Groups['Value'].Value.Trim()

                if (-not [string]::IsNullOrWhiteSpace($InlineValue)) {
                    if ($InlineValue -match '^\{\s*\}$') {
                        # An empty flow mapping - `permissions: {}` or `permissions: { }` - grants
                        # nothing and is compliant.
                        continue
                    }
                    elseif ($InlineValue -match '^\{(?<Body>.*)\}$') {
                        # A non-empty YAML flow mapping written on one line, e.g.
                        # `permissions: { contents: write }`. Parsed the same way the indented block
                        # below is: split on comma, then key: value per pair.
                        foreach ($Pair in ($Matches.Body -split ',')) {
                            if ($Pair -match '^\s*[a-z-]+:\s*(?<Value>.+?)\s*$') {
                                $PairValue = Get-YamlValueWithoutQuote -Value $Matches.Value
                                if ($PairValue -eq 'write') {
                                    [PSCustomObject]@{
                                        File = $File.Name
                                        Line = $PermissionsLineIndex + 1
                                        Raw  = $PermissionsLine.Trim()
                                    }
                                }
                            }
                        }
                        continue
                    }
                    else {
                        # A bare scalar, most notably `write-all` - the broadest grant GitHub offers,
                        # every scope, write, to every job. Matched as a whole token, not a
                        # substring, so a trailing comment mentioning "write" in prose can never turn
                        # a compliant line into a false offender.
                        $PlainValue = Get-YamlValueWithoutQuote -Value $InlineValue
                        if ($PlainValue -match '^(write|write-all)$') {
                            [PSCustomObject]@{
                                File = $File.Name
                                Line = $PermissionsLineIndex + 1
                                Raw  = $PermissionsLine.Trim()
                            }
                        }
                        continue
                    }
                }

                for ($LineIndex = $PermissionsLineIndex + 1; $LineIndex -lt $Lines.Count; $LineIndex++) {
                    $ScopeLine = $Lines[$LineIndex]
                    $ScopeLineStripped = Get-YamlLineWithoutComment -Line $ScopeLine

                    if ($ScopeLineStripped -match '^\s*$') {
                        # A blank line, or a line that was nothing but a comment - YAML permits
                        # either inside a block mapping, so keep scanning instead of stopping here.
                        continue
                    }
                    if ($ScopeLine -notmatch '^\s+\S') {
                        # A genuinely non-indented, non-blank line - the next top-level key, so the
                        # workflow-level permissions block has ended.
                        break
                    }
                    if ($ScopeLineStripped -match '^\s+[a-z-]+:\s*(?<Value>.+)$') {
                        $Value = Get-YamlValueWithoutQuote -Value $Matches.Value
                        if ($Value -eq 'write') {
                            [PSCustomObject]@{
                                File = $File.Name
                                Line = $LineIndex + 1
                                Raw  = $ScopeLine.Trim()
                            }
                        }
                    }
                }
            }

            $Detail = ($Offenders | ForEach-Object { "$($_.File):$($_.Line)  $($_.Raw)" }) -join "`n"
            $Offenders | Should -BeNullOrEmpty -Because "a workflow-level write scope hands it to every job, including ones that never need it - scope write permissions to the job that uses them instead`n$Detail"
        }
    }
}
