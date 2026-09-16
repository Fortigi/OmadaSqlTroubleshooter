#Requires -Version 7.0
# Direct tests for Switch-SessionLogFilePart (issue #143): the size-driven split - dispose, rename,
# replace the writer - asserting nothing written before the split is lost and the new writer is
# immediately usable. Real files and real handles throughout, as tests/Open-SessionLogFile.Tests.ps1
# already does for the rest of this feature.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Get-SessionLogFileName.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-SessionLogFile.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
}

Describe "Switch-SessionLogFilePart" -Tag "Unit" {

    BeforeEach {
        $Script:Folder = Join-Path ([System.IO.Path]::GetTempPath()) -ChildPath ("OmadaSqlLogSwitch_{0}" -f ([guid]::NewGuid().ToString("N")))
        [System.IO.Directory]::CreateDirectory($Script:Folder) | Out-Null
        $Script:ActivePath = Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter.log"
        $Script:StartTime = [datetime]::new(2026, 9, 14, 8, 5, 3)
        $Script:SessionLogFile = $null
    }

    AfterEach {
        if ($null -ne $Script:SessionLogFile -and $null -ne $Script:SessionLogFile.Writer) {
            try {
                $Script:SessionLogFile.Writer.Dispose()
            }
            catch {}
        }

        $Script:SessionLogFile = $null
        Remove-Item -LiteralPath $Script:Folder -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "A session writing the active file name" {

        BeforeEach {
            $Opened = Open-SessionLogFileWriter -Path $Script:ActivePath -SessionKey "20260914-080503" -StartTime $Script:StartTime -ProcessId 5151
            $Script:SessionLogFile = New-SessionLogFileState
            $Script:SessionLogFile.SessionKey = "20260914-080503"
            $Script:SessionLogFile.Directory = $Script:Folder
            $Script:SessionLogFile.Path = $Script:ActivePath
            $Script:SessionLogFile.StartTime = $Script:StartTime
            $Script:SessionLogFile.ProcessId = 5151
            $Script:SessionLogFile.Part = 1
            $Script:SessionLogFile.UsesActiveName = $true
            $Script:SessionLogFile.Writer = $Opened.Writer
            $Script:SessionLogFile.BytesWritten = $Opened.BytesWritten
            $Script:SessionLogFile.Writer.WriteLine("written before the split")
        }

        It "renames the finished part to part 1 and keeps everything written before the split" {
            Switch-SessionLogFilePart

            $FinishedPath = Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter_20260914-080503_001.log"
            Test-Path -LiteralPath $FinishedPath | Should -BeTrue
            (Get-Content -LiteralPath $FinishedPath -Raw) | Should -Match "written before the split"
        }

        It "opens a fresh, immediately usable writer at the same active path" {
            Switch-SessionLogFilePart

            $Script:SessionLogFile.Path | Should -BeExactly $Script:ActivePath
            $Script:SessionLogFile.Writer | Should -Not -BeNullOrEmpty
            { $Script:SessionLogFile.Writer.WriteLine("written after the split") } | Should -Not -Throw
            (Get-Content -LiteralPath $Script:ActivePath -Raw) | Should -Match "written after the split"
            (Get-Content -LiteralPath $Script:ActivePath -Raw) | Should -Not -Match "written before the split"
        }

        It "advances the part number one past the part it just finished" {
            Switch-SessionLogFilePart

            $Script:SessionLogFile.Part | Should -Be 2
        }

        It "continues past a part number that already exists in the folder" {
            $ExistingPart = Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter_20260914-080503_001.log"
            [System.IO.File]::WriteAllText($ExistingPart, "an earlier split already used part 1")

            Switch-SessionLogFilePart

            $Script:SessionLogFile.Part | Should -Be 3
            (Get-Content -LiteralPath $ExistingPart -Raw) | Should -Match "an earlier split already used part 1"
            $SecondPart = Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter_20260914-080503_002.log"
            (Get-Content -LiteralPath $SecondPart -Raw) | Should -Match "written before the split"
        }
    }

    Context "A session writing numbered parts directly, as a second instance does" {

        BeforeEach {
            $Script:PartOnePath = Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter_20260914-080503b_001.log"
            $Opened = Open-SessionLogFileWriter -Path $Script:PartOnePath -SessionKey "20260914-080503b" -StartTime $Script:StartTime -ProcessId 5151
            $Script:SessionLogFile = New-SessionLogFileState
            $Script:SessionLogFile.SessionKey = "20260914-080503b"
            $Script:SessionLogFile.Directory = $Script:Folder
            $Script:SessionLogFile.Path = $Script:PartOnePath
            $Script:SessionLogFile.StartTime = $Script:StartTime
            $Script:SessionLogFile.ProcessId = 5151
            $Script:SessionLogFile.Part = 1
            $Script:SessionLogFile.UsesActiveName = $false
            $Script:SessionLogFile.Writer = $Opened.Writer
            $Script:SessionLogFile.BytesWritten = $Opened.BytesWritten
            $Script:SessionLogFile.Writer.WriteLine("written to part 1")
        }

        It "leaves the finished numbered part exactly as it is, unrenamed" {
            Switch-SessionLogFilePart

            Test-Path -LiteralPath $Script:PartOnePath | Should -BeTrue
            (Get-Content -LiteralPath $Script:PartOnePath -Raw) | Should -Match "written to part 1"
        }

        It "opens part 2 as a fresh, immediately usable writer" {
            Switch-SessionLogFilePart

            $ExpectedPath = Join-Path $Script:Folder -ChildPath "OmadaSqlTroubleshooter_20260914-080503b_002.log"
            $Script:SessionLogFile.Path | Should -BeExactly $ExpectedPath
            $Script:SessionLogFile.Part | Should -Be 2
            { $Script:SessionLogFile.Writer.WriteLine("written to part 2") } | Should -Not -Throw
            (Get-Content -LiteralPath $ExpectedPath -Raw) | Should -Match "written to part 2"
        }
    }
}
