# Fixture responses for the mocked Omada backend. Routes on a normalized (lowercased, host-stripped)
# path + HTTP method + Body.dataType, never on exact strings (the app varies URL casing:
# jQGrid/JQGrid, WebService/webservice). All script:-scoped so the mock resolves them in module scope.

# --- Tunable state a scenario can set before acting ------------------------------------------------
$script:E2EEditorText = "SELECT 1"          # what the (mocked) Monaco editor "contains"
$script:E2ESelectedText = $null              # non-null => execute-selection mode
$script:E2EQueryList = @(                     # rows returned by Update-QueryList (DoIds are numeric)
    [pscustomobject]@{ Id = 100; DisplayName = "TestQuery" }
)
$script:E2EResultRows = @(                     # rows returned by a SqlDataProducer execute
    [pscustomobject]@{ Col1 = "a"; Col2 = "b" }
    [pscustomobject]@{ Col1 = "c"; Col2 = "d" }
)
$script:E2ENameClashRows = @()                # non-empty => Save-Query "as new" sees a duplicate name
$script:E2EConnectionProbeError = $null       # set to an ErrorRecord to simulate a failed connect
$script:E2EFixtureOverride = $null            # optional scriptblock($path,$method,$dataType,$body) -> @{ Value = ... } or $null

function script:Get-E2EEditorPayloadJson {
    # Invoke-ExecuteQuery expects a JSON *string* shaped { fullText, selectedText }.
    $Selected = if ($null -eq $script:E2ESelectedText) { $null } else { [string]$script:E2ESelectedText }
    return ([pscustomobject]@{ fullText = [string]$script:E2EEditorText; selectedText = $Selected } | ConvertTo-Json -Compress)
}

function script:New-E2EErrorRecord {
    param(
        [string]$Message = "Unauthorized",
        [System.Net.HttpStatusCode]$StatusCode = [System.Net.HttpStatusCode]::Unauthorized
    )
    $Exception = [System.Net.Http.HttpRequestException]::new($Message, $null, $StatusCode)
    return [System.Management.Automation.ErrorRecord]::new($Exception, "E2EMockError", [System.Management.Automation.ErrorCategory]::AuthenticationError, $null)
}

function script:Resolve-E2EFixture {
    param(
        $Uri,
        $Method,
        $Body
    )

    $Path = ([string]$Uri).ToLowerInvariant()
    $HttpMethod = ([string]$Method).ToUpperInvariant()
    $DataType = $null
    if ($null -ne $Body -and $Body -is [System.Collections.IDictionary] -and $Body.Contains("dataType")) {
        $DataType = [string]$Body["dataType"]
    }

    if ($null -ne $script:E2EFixtureOverride) {
        $Override = & $script:E2EFixtureOverride $Path $HttpMethod $DataType $Body
        if ($null -ne $Override) {
            return $Override.Value
        }
    }

    # Schema
    if ($Path -like "*syntaxhighlighting.asmx/getsqlschema*") {
        return ([pscustomobject]@{ d = [pscustomobject]@{ "dbo.Users" = @("Id int", "Name nvarchar"); "dbo.Roles" = @("Id int", "RoleName nvarchar") } })
    }

    # GetPagingData (three flavours by dataType)
    if ($Path -like "*getpagingdata*") {
        switch ($DataType) {
            "Views" {
                return ([pscustomobject]@{ d = [pscustomobject]@{ Records = 1; Rows = @([pscustomobject]@{ Id = "view-1"; Name = "SQL Troubleshooting" }) } })
            }
            "DataObjects" {
                $Row = [pscustomobject]@{}
                $Row | Add-Member -NotePropertyName "c-13" -NotePropertyValue 55
                $Row | Add-Member -NotePropertyName "c-2" -NotePropertyValue "me"
                $Row | Add-Member -NotePropertyName "c-4" -NotePropertyValue "me"
                return ([pscustomobject]@{ d = [pscustomobject]@{ Records = 1; Rows = @($Row) } })
            }
            "SqlDataProducer" {
                return ([pscustomobject]@{ d = [pscustomobject]@{ Records = @($script:E2EResultRows).Count; Rows = @($script:E2EResultRows) } })
            }
        }
    }

    # Data connection dropdown HTML
    if ($Path -like "*dataobjdlg.aspx*") {
        return '<select><option value="42" data-uid="uid-oises">OISES</option><option value="43" data-uid="uid-other">OtherDB</option></select>'
    }

    # Single query object by id: GET (fetch) / PUT (save existing) / DELETE (temp cleanup)
    if ($Path -like "*c_p_sqltroubleshooting(*") {
        if ($HttpMethod -eq "DELETE") {
            return ([pscustomobject]@{})
        }
        if ($HttpMethod -eq "GET") {
            return ([pscustomobject]@{ Id = 100; Name = "TestQuery"; DisplayName = "TestQuery"; C_QUERY = [string]$script:E2EEditorText })
        }
        # PUT
        return ([pscustomobject]@{ Id = 100; Name = "TestQuery"; DisplayName = "TestQuery" })
    }

    # Save-as-new duplicate-name check: ...?$filter=... and NAME eq '...'
    if ($Path -like "*c_p_sqltroubleshooting?*name eq*") {
        return ([pscustomobject]@{ Value = @($script:E2ENameClashRows) })
    }

    # Query list
    if ($Path -like "*c_p_sqltroubleshooting?*orderby*") {
        return ([pscustomobject]@{ value = @($script:E2EQueryList) })
    }

    # Save-as-new POST (create) -> ...C_P_SQLTROUBLESHOOTING (no parens, POST)
    if ($HttpMethod -eq "POST" -and $Path -like "*/c_p_sqltroubleshooting") {
        return ([pscustomobject]@{ Id = 200; Name = "NewQuery"; DisplayName = "NewQuery" })
    }

    # Bare probe (Test-OmadaConnection GET), or anything else on the OData endpoint
    if ($Path -like "*c_p_sqltroubleshooting*") {
        if ($null -ne $script:E2EConnectionProbeError) {
            return $script:E2EConnectionProbeError
        }
        return ([pscustomobject]@{ value = @() })
    }

    return ([pscustomobject]@{})
}
