#Requires -Version 7.0
# Set-EditorValue runs from five places while a tab loads, and each fetched the same query again on the
# UI thread - five round trips within 13 seconds in a cloud-PC log. A fetch is now reused briefly; what
# is asserted is that it is reused only when nothing can have changed it.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Get-RecentSqlQueryObject.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]

    function Write-LogOutput {
        param([Parameter(ValueFromPipeline = $true)]$InputObject, [string]$LogType, $ErrorObject, [switch]$SkipDialog)
        process { }
    }

    # The tenant. Counts the fetches and answers with whatever $script:TenantAnswer holds.
    function Get-SqlQueryObject {
        $script:Fetches++
        return $script:TenantAnswer
    }

    function script:Reset-QueryState {
        param([string]$SessionKey = "session-a", [string]$DoId = "6128075")

        $Script:RecentSqlQueryFetch = @{}
        $Script:RunTimeConfig = [pscustomobject]@{ ApplicationName = "Test" }
        $Script:RunTimeData = [pscustomobject]@{ RestMethodParam = @{ SessionKey = $SessionKey } }
        $Script:AppConfig = [pscustomobject]@{ CurrentSqlQuery = [pscustomobject]@{ DoId = $DoId } }

        $script:Fetches = 0
        $script:TenantAnswer = [pscustomobject]@{ Id = [int]$DoId; C_QUERY = "select 1" }
    }
}

Describe "Get-RecentSqlQueryObject - reuse within one load" {

    BeforeEach {
        Reset-QueryState
    }

    It "fetches once for five calls in a row" {
        foreach ($Private:Call in 1..5) {
            (Get-RecentSqlQueryObject).C_QUERY | Should -Be "select 1"
        }

        $script:Fetches | Should -Be 1
    }

    It "fetches again once the reuse window has passed" {
        Get-RecentSqlQueryObject | Out-Null
        $Script:RecentSqlQueryFetch["session-a|6128075"].FetchedUtc = [DateTime]::UtcNow.AddSeconds(-($Script:RecentSqlQueryMaxAgeSeconds + 1))

        Get-RecentSqlQueryObject | Out-Null

        $script:Fetches | Should -Be 2
    }

    It "fetches a different query separately" {
        Get-RecentSqlQueryObject | Out-Null
        $Script:AppConfig.CurrentSqlQuery.DoId = "5354019"

        Get-RecentSqlQueryObject | Out-Null

        $script:Fetches | Should -Be 2
    }

    It "fetches separately for another session" {
        # The same query on another tenant or identity is a different object.
        Get-RecentSqlQueryObject | Out-Null
        $Script:RunTimeData.RestMethodParam.SessionKey = "session-b"

        Get-RecentSqlQueryObject | Out-Null

        $script:Fetches | Should -Be 2
    }

    It "does not keep a failed fetch" {
        # Get-SqlQueryObject handles 404 and 401 itself and answers null; the next call must ask again.
        $script:TenantAnswer = $null
        Get-RecentSqlQueryObject | Should -BeNullOrEmpty

        $script:TenantAnswer = [pscustomobject]@{ Id = 6128075; C_QUERY = "select 2" }
        (Get-RecentSqlQueryObject).C_QUERY | Should -Be "select 2"

        $script:Fetches | Should -Be 2
    }
}

Describe "Clear-RecentSqlQueryObject - when a fetch may no longer be reused" {

    BeforeEach {
        Reset-QueryState
        Get-RecentSqlQueryObject | Out-Null
    }

    It "forgets one query, so a save or an execute is followed by a fresh read" {
        $script:TenantAnswer = [pscustomobject]@{ Id = 6128075; C_QUERY = "select saved" }

        Clear-RecentSqlQueryObject -DoId "6128075"

        (Get-RecentSqlQueryObject).C_QUERY | Should -Be "select saved"
        $script:Fetches | Should -Be 2
    }

    It "forgets that query for every session" {
        $Script:RecentSqlQueryFetch["session-b|6128075"] = @{ Result = "other"; FetchedUtc = [DateTime]::UtcNow }

        Clear-RecentSqlQueryObject -DoId "6128075"

        $Script:RecentSqlQueryFetch.Count | Should -Be 0
    }

    It "leaves other queries alone" {
        $Script:RecentSqlQueryFetch["session-a|5354019"] = @{ Result = "other"; FetchedUtc = [DateTime]::UtcNow }

        Clear-RecentSqlQueryObject -DoId "6128075"

        $Script:RecentSqlQueryFetch.ContainsKey("session-a|5354019") | Should -BeTrue
    }

    It "does not treat one DoId as a prefix of another" {
        $Script:RecentSqlQueryFetch["session-a|16128075"] = @{ Result = "other"; FetchedUtc = [DateTime]::UtcNow }

        Clear-RecentSqlQueryObject -DoId "6128075"

        $Script:RecentSqlQueryFetch.ContainsKey("session-a|16128075") | Should -BeTrue
    }

    It "forgets everything without a DoId, as a disconnect does" {
        Clear-RecentSqlQueryObject

        $Script:RecentSqlQueryFetch.Count | Should -Be 0
    }

    It "does nothing before anything was fetched" {
        $Script:RecentSqlQueryFetch = $null

        { Clear-RecentSqlQueryObject -DoId "6128075" } | Should -Not -Throw
    }
}

Describe "The callers clear it" {
    # Source assertions, as the repository does for other wiring: these functions need a live window to run.

    BeforeAll {
        $script:PrivatePath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "src\Lib\Functions\Private"
    }

    It "Set-EditorValue goes through the reuse" {
        Get-Content -Path (Join-Path $script:PrivatePath "Set-EditorValue.ps1") -Raw | Should -Match '\$Private:Result\s*=\s*Get-RecentSqlQueryObject'
    }

    It "Save-Query clears the query it saves, and still reads the tenant directly" {
        $Private:Source = Get-Content -Path (Join-Path $script:PrivatePath "Save-Query.ps1") -Raw
        $Private:Source | Should -Match 'Clear-RecentSqlQueryObject -DoId \$Script:AppConfig\.CurrentSqlQuery\.DoId'
        $Private:Source | Should -Match '\$private:Result\s*=\s*Get-SqlQueryObject'
    }

    It "Invoke-ExecuteQuery clears the selected query" {
        Get-Content -Path (Join-Path $script:PrivatePath "Invoke-ExecuteQuery.ps1") -Raw | Should -Match 'Clear-RecentSqlQueryObject -DoId'
    }

    It "Set-SqlConnectionState clears everything on disconnect" {
        Get-Content -Path (Join-Path $script:PrivatePath "Set-SqlConnectionState.ps1") -Raw | Should -Match '(?s)if \(-not \$Status\) \{\s*Clear-RecentSqlQueryObject\s*\}'
    }
}
