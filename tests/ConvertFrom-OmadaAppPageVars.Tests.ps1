#Requires -Version 7.0
# Issue #165. The parser for the settings Omada embeds in a page's `appPageVars` assignment.
#
# The payloads below are shaped after a real 16.0.99 page, reduced to the cases that decide whether
# the parser is right. Inline, following tests/Get-DataConnectionOptionList.Tests.ps1: there is no
# fixture directory in this repository and the interesting inputs are a few lines each.
#
# What makes this worth testing at all is that the block is NOT JSON. It is a JavaScript object
# literal whose values contain the very characters a naive parse would split on - braces inside
# custSettings, colons inside time spans and URLs, commas inside embedded JSON, and quotes inside
# escaped documents. Every Describe below is one of those.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "ConvertFrom-OmadaAppPageVars.ps1")

    # Every function in the file opens with the tracer preamble, which needs both of these.
    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:RunTimeConfig = [pscustomobject]@{ ApplicationName = "Test" }

    # Shaped after the real page: a bool, a single-quoted string, a time span whose colons must not be
    # read as separators, a nested JSON object, an array, and a JSON document carried as a string.
    $Script:RealisticPage = @'
<html><body><script type="text/JavaScript">appPageVars={customerId: 1000,
identityUserName: 'SYSTEM',
hasSessionCookie: false,
custSettings: {"aDTimeSpan":"00:01:00","oDWMaximumObjectsPerRequest":100,"authElementPermissions":"{}","uiHomePageActions":"{\"processes\":[{\"processName\":\"Onboard employee\"}]}","enableExportAudit":true},
gridEquipmentDims: '{ counterHeight: 32, defaults: true }',
languages: {"1000":"English","1005":"Dutch"},
isOISaaS: true,
isIngestionEnabled: true,
licenseWarning: []}</script></body></html>
'@
}

Describe "ConvertFrom-OmadaAppPageVars - the flag this feature needs" {

    It "reads isIngestionEnabled as a boolean, not the text 'true'" {
        # A string "true" would make every caller remember to compare text, and the callers ask a
        # yes/no question.
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html $Script:RealisticPage

        $Private:Setting["isIngestionEnabled"] | Should -BeOfType [bool]
        $Private:Setting["isIngestionEnabled"] | Should -BeTrue
    }

    It "reads it case-insensitively, because the caller should not have to match the page's spelling" {
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html $Script:RealisticPage

        $Private:Setting["ISINGESTIONENABLED"] | Should -BeTrue
    }

    It "distinguishes absent from false" {
        # The three-state contract. An older tenant that does not publish the flag has NOT said it is
        # off, and the filter must not treat the two alike.
        $Private:Page = "appPageVars={customerId: 1000,isOISaaS: true}"
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html $Private:Page

        $Private:Setting.Contains("isIngestionEnabled") | Should -BeFalse
    }

    It "reads an explicit false as false" {
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html "appPageVars={isIngestionEnabled: false}"

        $Private:Setting.Contains("isIngestionEnabled") | Should -BeTrue
        $Private:Setting["isIngestionEnabled"] | Should -BeFalse
    }
}

Describe "ConvertFrom-OmadaAppPageVars - the characters a naive parse would break on" {

    It "keeps a time span whole, rather than splitting it at its colons" {
        # The first colon at depth zero separates name from value; later ones belong to the value.
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html $Script:RealisticPage

        $Private:Setting["aDTimeSpan"] | Should -BeExactly "00:01:00"
    }

    It "finds the end of the block past the braces inside custSettings" {
        # A balanced-brace scan. Stopping at the first '}' would truncate the block and lose every
        # setting after custSettings - including the flag this feature reads.
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html $Script:RealisticPage

        $Private:Setting.Contains("isIngestionEnabled") | Should -BeTrue
        $Private:Setting.Contains("licenseWarning") | Should -BeTrue
    }

    It "does not treat a brace inside a string as structure" {
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html "appPageVars={label: 'a { b } c',isIngestionEnabled: true}"

        $Private:Setting["label"] | Should -BeExactly "a { b } c"
        $Private:Setting["isIngestionEnabled"] | Should -BeTrue
    }

    It "does not treat a comma inside embedded JSON as a pair separator" {
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html $Script:RealisticPage

        $Private:Setting["languages"]["1000"] | Should -BeExactly "English"
        $Private:Setting["languages"]["1005"] | Should -BeExactly "Dutch"
    }

    It "strips the quotes from a single-quoted string" {
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html $Script:RealisticPage

        $Private:Setting["identityUserName"] | Should -BeExactly "SYSTEM"
    }
}

Describe "ConvertFrom-OmadaAppPageVars - nested and escaped JSON" {

    It "parses custSettings into a dictionary" {
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html $Script:RealisticPage

        $Private:Setting["custSettings"] | Should -BeOfType [System.Collections.IDictionary]
        $Private:Setting["custSettings"]["oDWMaximumObjectsPerRequest"] | Should -Be 100
    }

    It "flattens custSettings so a caller need not know which level a setting lives on" {
        # isIngestionEnabled is top-level while most settings are nested. Callers ask for a name.
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html $Script:RealisticPage

        $Private:Setting["enableExportAudit"] | Should -BeTrue
    }

    It "unwraps a JSON document that is carried as an escaped string" {
        # uiHomePageActions is JSON inside a JSON string. One level of parsing leaves it as text.
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html $Script:RealisticPage

        $Private:Setting["uiHomePageActions"] | Should -BeOfType [System.Collections.IDictionary]
        @($Private:Setting["uiHomePageActions"]["processes"]).Count | Should -Be 1
    }

    It "parses a JS-ish object with bare keys, which ConvertFrom-Json accepts" {
        # Measured, not assumed, and this test was written the other way round first: gridEquipmentDims
        # has BARE keys, so the expectation was that ConvertFrom-Json would reject it and the raw
        # string would be kept. PowerShell 7 parses it. A dictionary is more useful to a caller than
        # the text, so the behaviour is kept and recorded here rather than forced back.
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html $Script:RealisticPage

        $Private:Setting["gridEquipmentDims"] | Should -BeOfType [System.Collections.IDictionary]
        $Private:Setting["gridEquipmentDims"]["counterHeight"] | Should -Be 32
    }

    It "parses a decimal under the invariant culture, not the host's" {
        # Raised in review on PR #168. The two-argument [double]::TryParse parses with the CURRENT
        # culture, so on a host whose culture uses "." as a group separator - de-DE, for instance -
        # 1.5 parses as 15. The appPageVars block is machine-generated JavaScript and is always
        # invariant, which makes the host's culture the wrong question to ask of it.
        #
        # The culture is switched for the duration of this test rather than asserted indirectly,
        # because the two-argument overload passes on an en-US agent and fails only elsewhere - which
        # is exactly how this reached review in the first place.
        $Private:Original = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::new("de-DE")

            $Private:Setting = ConvertFrom-OmadaAppPageVars -Html "appPageVars={ratio: 1.5,count: 1000}"

            $Private:Setting["ratio"] | Should -Be 1.5
            $Private:Setting["count"] | Should -Be 1000
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $Private:Original
        }
    }

    It "keeps text that is not an object at all" {
        # The fallback the try/catch is actually for. Without a case like this, nothing would notice if
        # the catch stopped working.
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html "appPageVars={note: '{ this is not json',isIngestionEnabled: true}"

        $Private:Setting["note"] | Should -BeOfType [string]
        $Private:Setting["note"] | Should -BeExactly "{ this is not json"
        $Private:Setting["isIngestionEnabled"] | Should -BeTrue
    }

    It "still reads the settings that follow the one it could not parse" {
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html $Script:RealisticPage

        $Private:Setting["isOISaaS"] | Should -BeTrue
    }
}

Describe "ConvertFrom-OmadaAppPageVars - pages it cannot read" {
    # None of these is an exceptional condition: a caller that cannot read a setting has to cope with
    # that anyway, and the filter's contract is to leave the connection list alone when it does not
    # know. So each returns an empty lookup rather than throwing.

    It "returns an empty lookup for a page with no appPageVars assignment" {
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html "<html><body>Please wait</body></html>"

        $Private:Setting.Count | Should -Be 0
    }

    It "returns an empty lookup for an unbalanced block" {
        # A truncated response. Guessing where the block should have ended would invent settings.
        $Private:Setting = ConvertFrom-OmadaAppPageVars -Html "appPageVars={customerId: 1000,custSettings: {"

        $Private:Setting.Count | Should -Be 0
    }

    It "returns an empty lookup for null, empty and whitespace" {
        (ConvertFrom-OmadaAppPageVars -Html $null).Count | Should -Be 0
        (ConvertFrom-OmadaAppPageVars -Html "").Count | Should -Be 0
        (ConvertFrom-OmadaAppPageVars -Html "   ").Count | Should -Be 0
    }

    It "does not throw on any of them" {
        { ConvertFrom-OmadaAppPageVars -Html $null } | Should -Not -Throw
        { ConvertFrom-OmadaAppPageVars -Html "appPageVars={" } | Should -Not -Throw
    }
}
