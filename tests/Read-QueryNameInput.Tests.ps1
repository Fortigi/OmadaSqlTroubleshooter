#Requires -Version 7.0
# A refused name is asked for again, with the reason and what was typed - a typo costs one correction.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = [System.IO.Path]::Combine($ParentPath, "src", "Lib", "Functions", "Private")
    . (Join-Path $PrivatePath "Test-SqlQueryName.ps1")
    . (Join-Path $PrivatePath "Read-QueryNameInput.ps1")

    # Each call answers with the next scripted reply: @{ Choice; Text }.
    $script:Replies = [System.Collections.Generic.Queue[object]]::new()
    $script:Asked = [System.Collections.Generic.List[object]]::new()
    function Open-ChoiceForm {
        param($Title, $Message, $LeftButtonText, $RightButtonText, [switch]$ShowInput, [string]$InputText)
        $script:Asked.Add([PSCustomObject]@{ Title = $Title; Message = $Message; Ok = $LeftButtonText; Cancel = $RightButtonText; ShowInput = [bool]$ShowInput; InputText = $InputText })
        $Reply = $script:Replies.Dequeue()
        $Script:ChoiceFormInputText = $Reply.Text
        return $Reply.Choice
    }
}

Describe 'Read-QueryNameInput' -Tag 'Unit' {
    BeforeEach {
        $script:Replies.Clear()
        $script:Asked.Clear()
    }

    It 'Should return the accepted, trimmed name' {
        $script:Replies.Enqueue(@{ Choice = $true; Text = "  New name " })

        $Result = Read-QueryNameInput -Title "Rename query" -Message "New name:" -DefaultName "Old" -OkText "Rename"

        $Result.Name | Should -Be "New name"
        $Result.IsValid | Should -BeTrue
        $script:Asked.Count | Should -Be 1
        $script:Asked[0].ShowInput | Should -BeTrue
        $script:Asked[0].InputText | Should -Be "Old"
        $script:Asked[0].Title | Should -Be "Rename query"
        $script:Asked[0].Message | Should -Be "New name:"
        $script:Asked[0].Ok | Should -Be "Rename"
        $script:Asked[0].Cancel | Should -Be "Cancel"
    }

    It 'Should return nothing when the user cancels (<Case>)' -ForEach @(
        @{ Case = 'Cancel'; Choice = $false }
        @{ Case = 'closing the dialog'; Choice = $null }
    ) {
        $script:Replies.Enqueue(@{ Choice = $Choice; Text = "Typed" })

        Read-QueryNameInput -DefaultName "Old" | Should -BeNullOrEmpty
    }

    It 'Should ask again after a refused name, with the reason and the text that was typed' {
        $script:Replies.Enqueue(@{ Choice = $true; Text = "Taken" })
        $script:Replies.Enqueue(@{ Choice = $true; Text = "Free" })

        $Result = Read-QueryNameInput -Message "Name:" -ExistingNames @("Taken")

        $Result.Name | Should -Be "Free"
        $script:Asked.Count | Should -Be 2
        $script:Asked[1].InputText | Should -Be "Taken"
        $script:Asked[1].Message | Should -Match "already exists"
        $script:Asked[1].Message | Should -Match "Name:$"
    }

    It 'Should report an unchanged rename as such' {
        $script:Replies.Enqueue(@{ Choice = $true; Text = "Same" })

        (Read-QueryNameInput -DefaultName "Same" -CurrentName "Same").IsUnchanged | Should -BeTrue
    }

    It 'Should stop asking when the user cancels after a refusal' {
        $script:Replies.Enqueue(@{ Choice = $true; Text = "" })
        $script:Replies.Enqueue(@{ Choice = $false; Text = "" })

        Read-QueryNameInput | Should -BeNullOrEmpty
        $script:Asked.Count | Should -Be 2
    }
}
