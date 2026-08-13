#Requires -Version 7.0
# Tests for the recorder's PII scrubbing. Pure string work - no server, cross-platform.

BeforeAll {
    . (Join-Path $PSScriptRoot "Sanitize-OmadaFixture.ps1")
}

Describe "ConvertTo-SanitizedOmadaFixture" {

    It "replaces the tenant host and username with placeholders" {
        $Map = New-OmadaScrubMap -TenantHost "acme.omada.cloud" -UserName @("ACME\m.jansen")
        $Clean = ConvertTo-SanitizedOmadaFixture -Content '{"url":"https://acme.omada.cloud/odata","who":"ACME\\m.jansen"}' -ScrubMap $Map

        $Clean | Should -Not -Match "acme\.omada\.cloud"
        $Clean | Should -Not -Match "m\.jansen"
        $Clean | Should -Match "tenant\.omada\.cloud"
    }

    It "applies longer keys first so a shorter key cannot mask a more specific one" {
        # The bare host is inserted first, but the longer host+path entry must still win - otherwise
        # rewriting the host leaves 'host/secret-path' unmatchable and the specific PII survives.
        $Map = New-OmadaScrubMap -TenantHost "acme.omada.cloud" -Extra @{ "acme.omada.cloud/secret-report" = "tenant.omada.cloud/report" }
        $Clean = ConvertTo-SanitizedOmadaFixture -Content "see https://acme.omada.cloud/secret-report today" -ScrubMap $Map

        $Clean | Should -Not -Match "secret-report"
        $Clean | Should -Match "tenant\.omada\.cloud/report"
    }

    It "scrubs a domain account that appears JSON-escaped in recorded content" {
        # The recorder writes ConvertTo-Json output, so "ACME\m.jansen" lands in the file as
        # "ACME\\m.jansen". Matching only the raw form would leak the account name.
        $Map = New-OmadaScrubMap -TenantHost "acme.omada.cloud" -UserName @("ACME\m.jansen")
        $Recorded = @{ who = "ACME\m.jansen" } | ConvertTo-Json -Compress

        $Clean = ConvertTo-SanitizedOmadaFixture -Content $Recorded -ScrubMap $Map

        $Clean | Should -Not -Match "jansen"
        # Still valid JSON, and the placeholder survives a round-trip.
        ($Clean | ConvertFrom-Json).who | Should -Be "MOCK\serviceaccount"
    }

    It "redacts email addresses even when not in the scrub map" {
        $Clean = ConvertTo-SanitizedOmadaFixture -Content '{"mail":"Mark.van.Eijken@queriosit.nl"}' -ScrubMap $null
        $Clean | Should -Not -Match "queriosit"
        $Clean | Should -Match "user@example\.com"
    }

    It "keeps GUIDs by default but replaces them consistently with -ScrubGuids" {
        $Content = '{"a":"3f2504e0-4f89-11d3-9a0c-0305e82c3301","b":"3f2504e0-4f89-11d3-9a0c-0305e82c3301"}'

        (ConvertTo-SanitizedOmadaFixture -Content $Content -ScrubMap $null) | Should -Match "3f2504e0"

        $Scrubbed = ConvertTo-SanitizedOmadaFixture -Content $Content -ScrubMap $null -ScrubGuids
        $Scrubbed | Should -Not -Match "3f2504e0"
        # The same source GUID must map to the same placeholder so rows stay distinguishable.
        ([regex]::Matches($Scrubbed, '00000000-0000-0000-0000-000000000000')).Count | Should -Be 2
    }

    It "leaves content untouched when there is nothing to scrub" {
        $Content = '{"DisplayName":"Users","Number":"IDG-900"}'
        ConvertTo-SanitizedOmadaFixture -Content $Content -ScrubMap (New-OmadaScrubMap) | Should -Be $Content
    }
}
