function Get-ConfigSchemaDefault {
    <#
    .SYNOPSIS
    Returns the default value declared for a property in the global configuration schema.

    .DESCRIPTION
    The schema is the single source of truth for a configuration default. Reading it here keeps
    defaults out of the code, so a value such as the log level default is declared in exactly one
    place instead of being repeated as a literal in every code path that needs a fallback.

    .PARAMETER Property
    The name of the global configuration property whose default is wanted.

    .PARAMETER SchemaPath
    An alternative schema file to read. Intended for tests; when omitted the module's own global
    configuration schema is used and cached for the rest of the session.
    #>
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Property,
        [Parameter(Mandatory = $false)]
        [string]$SchemaPath
    )

    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))

        if (![string]::IsNullOrWhiteSpace($SchemaPath)) {
            $SchemaProperties = Get-Content $SchemaPath -Raw | ConvertFrom-Json
        }
        else {
            # Reuses the cache Set-ConfigProperty fills, so the schema is read from disk once.
            if ($null -eq $Script:GlobalConfigProperties) {
                $Script:GlobalConfigProperties = Get-Content (Join-Path (Get-ModuleBaseFolder) -ChildPath "lib\schema\appGlobalConfigSchema.json") -Raw | ConvertFrom-Json
            }
            $SchemaProperties = $Script:GlobalConfigProperties
        }

        $PropertyDefinition = $SchemaProperties | Where-Object { $_.Name -eq $Property } | Select-Object -First 1
        if ($null -eq $PropertyDefinition) {
            "Property '{0}' was not found in the global config schema!" -f $Property | Write-LogOutput -LogType WARNING -SkipDialog
            return $null
        }

        return $PropertyDefinition.DefaultValue
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
