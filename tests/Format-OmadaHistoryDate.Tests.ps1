#Requires -Version 7.0
# Review finding on PR #100: making ConvertTo-OmadaHistoryDate return $null for an unreadable date
# (issue #95) makes ChangeDate nullable everywhere it is DISPLAYED. Without this helper the failure
# simply moves from the fetch to the first click - $null.ToString() throws "You cannot call a method
# on a null-valued expression" - which would undo the point of the fix.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $SourcePath = Join-Path $ParentPath -ChildPath "src\Lib"
    $PrivatePath = Join-Path $SourcePath -ChildPath "Functions\Private"
    . (Join-Path $PrivatePath -ChildPath "Format-OmadaHistoryDate.ps1")

    $script:EventsPath = Join-Path $SourcePath -ChildPath "Events"
    $script:XamlPath = Join-Path $SourcePath -ChildPath "ui\SqlHistoryForm.xaml"
}

Describe "Format-OmadaHistoryDate" {
    It "renders a date in the format the history window has always shown" {
        Format-OmadaHistoryDate -Value ([DateTime]::new(2026, 8, 25, 12, 3, 4)) | Should -Be "2026-08-25 12:03:04"
    }

    It "does not throw on the null that an unreadable date now produces" {
        { Format-OmadaHistoryDate -Value $null } | Should -Not -Throw
    }

    It "says the date is unknown rather than showing an empty cell" {
        # An empty string would be indistinguishable from a row that genuinely has no date.
        Format-OmadaHistoryDate -Value $null | Should -Be "(unknown)"
    }

    # A fixed format string is NOT a fixed rendering - the calendar and the digits still come from
    # the current culture. These are the cultures that prove it: nl-NL cannot, because it shares the
    # Gregorian calendar and ASCII digits with en-US, so an nl-NL test would pass on the culture-
    # sensitive code and claim to have checked this.
    It "renders the same way under <Culture>, whose calendar is not Gregorian" -ForEach @(
        @{ Culture = "th-TH" }  # Buddhist era - the year would read 2569
        @{ Culture = "ar-SA" }  # Hijri - the whole date would read 1448-03-12
        @{ Culture = "nl-NL" }
        @{ Culture = "en-US" }
    ) {
        $Private:Previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
            Format-OmadaHistoryDate -Value ([DateTime]::new(2026, 8, 25, 12, 3, 4)) | Should -Be "2026-08-25 12:03:04"
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $Private:Previous
        }
    }
}

Describe "Every place a change date is displayed" {
    # These are source assertions rather than behavioural ones: the call sites are WPF event
    # handlers, which cannot be invoked headlessly. What they defend is the thing that actually went
    # wrong - a .ToString() on a value that is now nullable.
    It "no longer calls .ToString() on a change date" {
        $Private:Handlers = Get-ChildItem -Path $script:EventsPath -Filter "SqlHistoryForm.Elements.*.ps1"
        $Private:Handlers | Should -Not -BeNullOrEmpty

        foreach ($Private:Handler in $Private:Handlers) {
            $Private:Source = Get-Content -Path $Private:Handler.FullName -Raw
            $Private:Source | Should -Not -Match 'ChangeDate\.ToString' -Because "$($Private:Handler.Name) would throw on a row whose date could not be read"
        }
    }

    It "shows the same placeholder in the grid as in the detail pane" {
        $Private:Xaml = Get-Content -Path $script:XamlPath -Raw

        # Quoted, because a markup-extension value starting with "(" is otherwise read as attached
        # property syntax.
        $Private:Xaml | Should -Match "TargetNullValue='\(unknown\)'"
    }
}
