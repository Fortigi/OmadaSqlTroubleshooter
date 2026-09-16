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
    }
}
