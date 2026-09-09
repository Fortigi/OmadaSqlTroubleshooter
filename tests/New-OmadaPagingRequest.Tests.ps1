#Requires -Version 7.0
# Issue #90, slice A. The point of this builder is that the UI thread and the worker send the SAME
# request; these tests are mostly about that equality, not about the shape in isolation.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $script:PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    . (Join-Path $script:PrivatePath -ChildPath "New-OmadaPagingRequest.ps1")

    # The code, without its comments. A purity scan over raw source is defeated by its own
    # documentation: this function's help explains why it may not read $Script: state, and a naive
    # match then fails on the explanation rather than on a violation.
    function script:Get-CodeOnly {
        param([string]$Path)
        $Private:Tokens = $null
        $Private:Errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Private:Tokens, [ref]$Private:Errors)
        return (($Private:Tokens | Where-Object { $_.Kind -ne "Comment" }).Text -join " ")
    }
}

Describe "New-OmadaPagingRequest" {
    It "posts to the jqGrid paging endpoint" {
        $Private:Request = New-OmadaPagingRequest -DataType "Views" -DataTypeArgs @{ OwnerShipType = "Both" } -BaseUrl "https://tenant.omada.cloud"

        $Private:Request.Method | Should -Be "POST"
        $Private:Request.Uri | Should -Be "https://tenant.omada.cloud/WebService/JQGridPopulationWebService.asmx/GetPagingData"
    }

    It "carries the data type and its arguments through untouched" {
        $Private:Args = [ordered]@{ viewId = "42"; countRows = $false }

        $Private:Request = New-OmadaPagingRequest -DataType "DataObjects" -DataTypeArgs $Private:Args -BaseUrl "https://tenant.omada.cloud"

        $Private:Request.Body.dataType | Should -Be "DataObjects"
        $Private:Request.Body.dataTypeArgs.viewId | Should -Be "42"
        $Private:Request.Body.dataTypeArgs.countRows | Should -Be $false
    }

    Context "Searching" {
        It "sets both the sort index and the search string together" {
            # sidx and searchString move as a pair in the original code; splitting them is the
            # plausible way to break this builder without any single assertion noticing.
            $Private:Request = New-OmadaPagingRequest -DataType "Views" -DataTypeArgs @{} -SearchString "SQL Troubleshooting" -BaseUrl "https://t"

            $Private:Request.Body.sidx | Should -Be "name"
            $Private:Request.Body.searchString | Should -Be "SQL Troubleshooting"
        }

        It "leaves both empty when there is nothing to search for" {
            $Private:Request = New-OmadaPagingRequest -DataType "Views" -DataTypeArgs @{} -BaseUrl "https://t"

            $Private:Request.Body.sidx | Should -BeNullOrEmpty
            $Private:Request.Body.searchString | Should -BeNullOrEmpty
        }

        It "treats whitespace as nothing to search for" {
            $Private:Request = New-OmadaPagingRequest -DataType "Views" -DataTypeArgs @{} -SearchString "   " -BaseUrl "https://t"

            $Private:Request.Body.sidx | Should -BeNullOrEmpty
        }
    }

    It "sends the cache-busting nd value this application has always sent" {
        # A constant where jqGrid would send a timestamp. Asserted because it is exactly the kind of
        # value that quietly becomes two different constants once it exists in two places - which is
        # the reason this builder exists at all.
        (New-OmadaPagingRequest -DataType "Views" -DataTypeArgs @{} -BaseUrl "https://t").Body.nd | Should -Be 1732546553116
    }

    It "defaults to the page size the application has always requested" {
        (New-OmadaPagingRequest -DataType "Views" -DataTypeArgs @{} -BaseUrl "https://t").Body.rows | Should -Be 1000
    }

    It "asks for one page, unsearched, ascending" {
        $Private:Body = (New-OmadaPagingRequest -DataType "Views" -DataTypeArgs @{} -BaseUrl "https://t").Body

        $Private:Body._search | Should -Be $false
        $Private:Body.page | Should -Be 1
        $Private:Body.sord | Should -Be "asc"
    }

    It "is a pure function - no script state, no network" {
        # If this ever stops being true it cannot run in a worker runspace, where none of that
        # exists. Cheaper to assert here than to discover from a CommandNotFoundException inside a
        # background job.
        $Private:Code = Get-CodeOnly -Path (Join-Path $script:PrivatePath "New-OmadaPagingRequest.ps1")

        $Private:Code | Should -Not -Match '\$Script:'
        $Private:Code | Should -Not -Match 'Write-LogOutput'
        $Private:Code | Should -Not -Match 'Invoke-Omada'
    }
}

Describe "Get-OmadaGetPagingDataObject uses it" {
    It "no longer builds the body inline" {
        # The equality that matters: one definition, so the inline and background paths cannot drift.
        $Private:Source = Get-Content -Path (Join-Path $script:PrivatePath "Get-OmadaGetPagingDataObject.ps1") -Raw

        $Private:Source | Should -Match 'New-OmadaPagingRequest'
        $Private:Source | Should -Not -Match 'nd\s+=\s+1732546553116'
    }
}
