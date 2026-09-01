BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $FunctionPath = Join-Path $ParentPath -ChildPath "src\lib\functions\Private"
    . (Join-Path $FunctionPath -ChildPath "Get-ConfigSchemaDefault.ps1")
    # The tracer preamble of the function under test redacts its bound parameters.
    . (Join-Path $FunctionPath -ChildPath "ConvertTo-RedactedLogString.ps1")
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [PSCustomObject]@{ ApplicationName = "Test" }

    $Script:GlobalSchemaPath = Join-Path $ParentPath -ChildPath "src\lib\schema\appGlobalConfigSchema.json"

    # Keep the WARNING branch of the function under test out of the console and away from a dialog.
    function Write-LogOutput {
        param(
            [parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
            [string]$Message,
            $ErrorObject,
            [string]$LogType = "INFO",
            [switch]$SkipDialog
        )
    }
}

Describe 'Get-ConfigSchemaDefault' {

    It 'returns the default declared in the global config schema' {
        Get-ConfigSchemaDefault -Property "LogLevel" -SchemaPath $Script:GlobalSchemaPath | Should -BeExactly "WARNING"
    }

    It 'returns a non-string default unchanged' {
        Get-ConfigSchemaDefault -Property "TabCapacity" -SchemaPath $Script:GlobalSchemaPath | Should -Be 8
    }

    It 'returns $null for a property that declares no default' {
        Get-ConfigSchemaDefault -Property "LastOutputFolder" -SchemaPath $Script:GlobalSchemaPath | Should -BeNullOrEmpty
    }

    It 'returns $null for an unknown property instead of throwing' {
        { Get-ConfigSchemaDefault -Property "NoSuchProperty" -SchemaPath $Script:GlobalSchemaPath } | Should -Not -Throw
        Get-ConfigSchemaDefault -Property "NoSuchProperty" -SchemaPath $Script:GlobalSchemaPath | Should -BeNullOrEmpty
    }

    It 'declares Property as mandatory' {
        $ParameterMetadata = (Get-Command Get-ConfigSchemaDefault).Parameters["Property"]
        $Attribute = $ParameterMetadata.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        $Attribute.Mandatory | Should -Contain $true
    }
}

Describe 'Global config schema log level default' {

    BeforeAll {
        $Script:GlobalSchema = Get-Content $Script:GlobalSchemaPath -Raw | ConvertFrom-Json
        $Script:LogLevelDefinition = $Script:GlobalSchema | Where-Object { $_.Name -eq "LogLevel" }
    }

    It 'declares a default for LogLevel, so the schema can be the single source of truth' {
        $Script:LogLevelDefinition | Should -Not -BeNullOrEmpty
        $Script:LogLevelDefinition.DefaultValue | Should -Not -BeNullOrEmpty
    }

    It 'declares WARNING, matching the out-of-the-box behaviour the application has always had' {
        $Script:LogLevelDefinition.DefaultValue | Should -BeExactly "WARNING"
    }
}
