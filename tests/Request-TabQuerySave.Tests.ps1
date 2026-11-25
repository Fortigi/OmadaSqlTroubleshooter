#Requires -Version 7.0

BeforeAll {
    . (Join-Path $PSScriptRoot "CloseFlow.Shared.ps1")
    . (Join-Path $Script:QueryPrivatePath "Request-TabQuerySave.ps1")

    function Save-TabQueryForClose { param($TabSession, $Kind) }
}

Describe 'Request-TabQuerySave' -Tag 'Unit' {
    BeforeEach {
        New-QueryTestState
        Mock Save-TabQueryForClose { "Saved" }
    }

    It 'Should offer Save, Don''t save and Cancel, with Cancel as the third button' {
        Mock Open-ChoiceForm { "Save" }

        $null = Request-TabQuerySave -TabSession $script:TestTab -Kind SaveExisting

        Should -Invoke Open-ChoiceForm -Times 1 -Exactly -ParameterFilter {
            $LeftButtonText -eq "Save" -and $RightButtonText -eq "Don't save" -and $ExtraButtonText -eq "Cancel" -and
            $LeftButtonReturnValue -eq "Save" -and $RightButtonReturnValue -eq "Discard" -and $ExtraButtonReturnValue -eq "Cancel" -and
            $Message -match "Save changes to query 'Query1'"
        }
    }

    It 'Should say what happens to an ad-hoc query when the application closes' {
        Mock Open-ChoiceForm { "Discard" }

        $null = Request-TabQuerySave -TabSession $script:TestTab -Kind SaveNew -ClosingApplication

        Should -Invoke Open-ChoiceForm -Times 1 -Exactly -ParameterFilter { $Message -match "offered again" }
    }

    It 'Should save on Save' {
        Mock Open-ChoiceForm { "Save" }

        Request-TabQuerySave -TabSession $script:TestTab -Kind SaveNew | Should -Be "Saved"
        Should -Invoke Save-TabQueryForClose -Times 1 -Exactly -ParameterFilter { $Kind -eq "SaveNew" -and $TabSession.Id -eq "tab-1" }
    }

    It 'Should discard on Don''t save, without saving' {
        Mock Open-ChoiceForm { "Discard" }

        Request-TabQuerySave -TabSession $script:TestTab -Kind SaveExisting | Should -Be "Discarded"
        Should -Invoke Save-TabQueryForClose -Times 0 -Exactly
    }

    It 'Should cancel on <Case>' -ForEach @(
        @{ Case = 'Cancel'; Answer = "Cancel" }
        @{ Case = 'closing the dialog'; Answer = $null }
    ) {
        Mock Open-ChoiceForm { $Answer }

        Request-TabQuerySave -TabSession $script:TestTab -Kind SaveExisting | Should -Be "Cancel"
        Should -Invoke Save-TabQueryForClose -Times 0 -Exactly
    }

    It 'Should cancel when the name prompt is cancelled' {
        Mock Open-ChoiceForm { "Save" }
        Mock Save-TabQueryForClose { "Cancelled" }

        Request-TabQuerySave -TabSession $script:TestTab -Kind SaveNew | Should -Be "Cancel"
    }

    It 'Should ask whether to close anyway after a failed save (<Answer>)' -ForEach @(
        @{ Answer = $true; Expected = "Discarded" }
        @{ Answer = $false; Expected = "Cancel" }
        @{ Answer = $null; Expected = "Cancel" }
    ) {
        $script:Answers = [System.Collections.Generic.Queue[object]]::new(@("Save", $Answer))
        Mock Open-ChoiceForm { $script:Answers.Dequeue() }
        Mock Save-TabQueryForClose { "Failed" }

        Request-TabQuerySave -TabSession $script:TestTab -Kind SaveExisting | Should -Be $Expected
        Should -Invoke Open-ChoiceForm -Times 1 -Exactly -ParameterFilter { $Title -eq "Not saved" -and $LeftButtonText -eq "Close anyway" -and $Message -match "'Query1' could not be saved" }
    }

    It 'Should offer only Close or Cancel for a tab that cannot save (<Answer>)' -ForEach @(
        @{ Answer = $true; Expected = "Discarded" }
        @{ Answer = $false; Expected = "Cancel" }
    ) {
        Mock Open-ChoiceForm { $Answer }

        Request-TabQuerySave -TabSession $script:TestTab -Kind Unavailable | Should -Be $Expected
        Should -Invoke Open-ChoiceForm -Times 1 -Exactly -ParameterFilter { $LeftButtonText -eq "Close" -and $RightButtonText -eq "Cancel" -and $null -eq $ExtraButtonText -and $Message -match "disconnected" }
        Should -Invoke Save-TabQueryForClose -Times 0 -Exactly
    }

    It 'Should speak of a new query, not of closing, for New' {
        Mock Open-ChoiceForm { "Save" }

        $null = Request-TabQuerySave -TabSession $script:TestTab -Kind SaveExisting -NewQuery

        Should -Invoke Open-ChoiceForm -Times 1 -Exactly -ParameterFilter { $Message -match "before starting a new query" }
    }

    It 'Should offer to discard rather than close for New (<Case>)' -ForEach @(
        @{ Case = 'disconnected'; Kind = "Unavailable"; ExpectedTitle = "Unsaved changes"; Button = "Discard"; Saved = "n/a" }
        @{ Case = 'failed save'; Kind = "SaveExisting"; ExpectedTitle = "Not saved"; Button = "Discard anyway"; Saved = "Failed" }
    ) {
        $script:Answers = [System.Collections.Generic.Queue[object]]::new(@("Save", $true, $true))
        Mock Open-ChoiceForm { $script:Answers.Dequeue() }
        Mock Save-TabQueryForClose { $Saved }

        $null = Request-TabQuerySave -TabSession $script:TestTab -Kind $Kind -NewQuery

        Should -Invoke Open-ChoiceForm -Times 1 -Exactly -ParameterFilter { $Title -eq $ExpectedTitle -and $LeftButtonText -eq $Button }
    }

    It 'Should speak of opening another query, and offer to discard, for Open' {
        Mock Open-ChoiceForm { $true }

        Request-TabQuerySave -TabSession $script:TestTab -Kind Unavailable -OpenQuery | Should -Be "Discarded"

        Should -Invoke Open-ChoiceForm -Times 1 -Exactly -ParameterFilter { $LeftButtonText -eq "Discard" -and $Message -match "Discard them anyway" }

        Mock Open-ChoiceForm { "Save" }
        $null = Request-TabQuerySave -TabSession $script:TestTab -Kind SaveExisting -OpenQuery
        Should -Invoke Open-ChoiceForm -Times 1 -Exactly -ParameterFilter { $Message -match "before opening another query" }
    }
}
