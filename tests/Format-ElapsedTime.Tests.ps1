#Requires -Version 7.0
# The status bar's query-time indicator used to be rendered three separate times with TimeSpan's
# default format - "00:00:03.1234567" - and refreshed once a second. Seven fractional digits updated
# at 1 Hz is what made a running query look jittery: six of those digits are noise, and the ones that
# are not sat frozen and then jumped by ten tenths at a time.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Format-ElapsedTime.ps1")
}

Describe "Format-ElapsedTime" {
    It "renders tenths, not ticks" {
        Format-ElapsedTime -TimeSpan ([TimeSpan]::FromSeconds(3.1234567)) | Should -Be "00:00:03.1"
    }

    It "renders zero the way a reset status bar shows it" {
        Format-ElapsedTime -TimeSpan ([TimeSpan]::Zero) | Should -Be "00:00:00.0"
    }

    It "pads every field to a fixed width, so the indicator does not jump about as it counts" {
        Format-ElapsedTime -TimeSpan ([TimeSpan]::FromSeconds(5)) | Should -Be "00:00:05.0"
        Format-ElapsedTime -TimeSpan ([TimeSpan]::FromSeconds(65)) | Should -Be "00:01:05.0"
        Format-ElapsedTime -TimeSpan ([TimeSpan]::FromSeconds(3725)) | Should -Be "01:02:05.0"
    }

    It "truncates the tenth rather than rounding it, so the number never runs ahead of the clock" {
        Format-ElapsedTime -TimeSpan ([TimeSpan]::FromMilliseconds(1999)) | Should -Be "00:00:01.9"
    }

    It "keeps counting past a day instead of silently rolling over" {
        # A query left running overnight should read 26 hours, not 2. "hh" in a TimeSpan format string
        # would have shown 02, which is the same string a two-hour query produces.
        Format-ElapsedTime -TimeSpan ([TimeSpan]::FromHours(26) + [TimeSpan]::FromSeconds(14)) | Should -Be "26:00:14.0"
    }

    It "renders a negative duration as zero" {
        # Possible if the system clock moves backwards while a request is in flight. A status bar
        # counting downwards past zero would look like a bug in the query, not in the clock.
        Format-ElapsedTime -TimeSpan ([TimeSpan]::FromSeconds(-5)) | Should -Be "00:00:00.0"
    }

    It "returns a string, so callers can assign it straight to a TextBlock" {
        Format-ElapsedTime -TimeSpan ([TimeSpan]::FromSeconds(1)) | Should -BeOfType [string]
    }
}
