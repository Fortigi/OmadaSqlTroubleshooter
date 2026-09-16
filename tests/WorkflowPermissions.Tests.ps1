#Requires -Version 7.0

BeforeAll {
    $Script:RepositoryRoot = Split-Path -Path $PSScriptRoot -Parent
    $Script:WorkflowsPath = Join-Path -Path $Script:RepositoryRoot -ChildPath '.github\workflows'

    $Script:WorkflowFiles = @(Get-ChildItem -Path $Script:WorkflowsPath -Filter '*.yml' -File) +
        @(Get-ChildItem -Path $Script:WorkflowsPath -Filter '*.yaml' -File)
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
                if ($PermissionsLine -match '^permissions:\s*\{\}\s*$') {
                    continue
                }

                # An inline value on the permissions: line itself, most notably `write-all` - the
                # broadest grant GitHub offers, every scope, write, to every job. It never appears
                # as an indented child line below, so without this branch the inner loop would walk
                # straight past it and this test would be blind to the worst possible offender.
                $InlineValue = [regex]::Match($PermissionsLine, '^permissions:\s*(?<Value>\S.*)$').Groups['Value'].Value
                if (-not [string]::IsNullOrWhiteSpace($InlineValue)) {
                    if ($InlineValue -match 'write') {
                        [PSCustomObject]@{
                            File = $File.Name
                            Line = $PermissionsLineIndex + 1
                            Raw  = $PermissionsLine.Trim()
                        }
                    }
                    continue
                }

                for ($LineIndex = $PermissionsLineIndex + 1; $LineIndex -lt $Lines.Count; $LineIndex++) {
                    $ScopeLine = $Lines[$LineIndex]
                    if ($ScopeLine -notmatch '^\s+\S') {
                        break
                    }
                    if ($ScopeLine -match '^\s+[a-z-]+:\s*write\s*$') {
                        [PSCustomObject]@{
                            File = $File.Name
                            Line = $LineIndex + 1
                            Raw  = $ScopeLine.Trim()
                        }
                    }
                }
            }

            $Detail = ($Offenders | ForEach-Object { "$($_.File):$($_.Line)  $($_.Raw)" }) -join "`n"
            $Offenders | Should -BeNullOrEmpty -Because "a workflow-level write scope hands it to every job, including ones that never need it - scope write permissions to the job that uses them instead`n$Detail"
        }
    }
}
