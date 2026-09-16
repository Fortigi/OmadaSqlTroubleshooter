#Requires -Version 7.0
# Direct tests for Test-SessionLogFileInUse (issue #143): opens the file exclusively and closes it
# at once, so the answer depends on what the operating system actually allows right now - not on
# any state this module tracks itself. Real handles only; a mock would prove nothing here.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"

    . (Join-Path $PrivatePath -ChildPath "Remove-ExcessSessionLogFile.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
}

Describe "Test-SessionLogFileInUse" -Tag "Unit" {

    BeforeEach {
        $Script:Folder = Join-Path ([System.IO.Path]::GetTempPath()) -ChildPath ("OmadaSqlLogInUse_{0}" -f ([guid]::NewGuid().ToString("N")))
        [System.IO.Directory]::CreateDirectory($Script:Folder) | Out-Null
        $Script:FilePath = Join-Path $Script:Folder -ChildPath "candidate.log"
        $Script:OpenHandle = $null
    }

    AfterEach {
        if ($null -ne $Script:OpenHandle) {
            try {
                $Script:OpenHandle.Dispose()
            }
            catch {}
        }

        Remove-Item -LiteralPath $Script:Folder -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "A closed file" {

        It "is not reported in use" {
            [System.IO.File]::WriteAllText($Script:FilePath, "content")

            Test-SessionLogFileInUse -Path $Script:FilePath | Should -BeFalse
        }
    }

    Context "A file genuinely held open" {

        It "is reported in use while a real handle holds it, even one that shares read and write" {
            [System.IO.File]::WriteAllText($Script:FilePath, "content")
            $Script:OpenHandle = [System.IO.FileStream]::new($Script:FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)

            Test-SessionLogFileInUse -Path $Script:FilePath | Should -BeTrue
        }

        It "is no longer reported in use once the real handle is closed" {
            [System.IO.File]::WriteAllText($Script:FilePath, "content")
            $Handle = [System.IO.FileStream]::new($Script:FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $Handle.Dispose()

            Test-SessionLogFileInUse -Path $Script:FilePath | Should -BeFalse
        }
    }

    Context "A path that cannot be opened at all" {

        It "reports a file that does not exist as in use" {
            $Missing = Join-Path $Script:Folder -ChildPath "does-not-exist.log"

            Test-SessionLogFileInUse -Path $Missing | Should -BeTrue
        }
    }
}
