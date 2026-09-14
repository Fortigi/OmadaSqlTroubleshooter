#Requires -Version 7.0
# The non-negotiable constraint of issue #121: the session log file sits BEHIND Protect-LogMessage,
# never beside it.
#
# A log window holds its contents until the process ends. A file holds them until somebody deletes
# it, on a machine that gets backed up, copied to a support ticket and attached to an email. A file
# writer that took its own copy of a message would therefore put unredacted credentials, tokens,
# result data and query text on disk permanently - a regression of #39 and #111, and strictly worse
# than the problem the file was added to solve.
#
# Two kinds of assertion guard that, because either alone can be defeated:
#
#   * the structural ones read the source and fail if the writer is ever called from anywhere other
#     than Write-LogOutput, or from a point in Write-LogOutput before the message is masked. Those
#     are the tests that fail if someone later routes around the gate.
#   * the end-to-end ones drive the real Write-LogOutput and then read the real file off disk, so
#     the guarantee is asserted on bytes rather than on the shape of the code.
#
# This suite guards a repository-wide invariant rather than a single function, which is why
# psakeBuild's Test task lists it as always-run: a change that moved the writer would otherwise skip
# the very test that exists to catch it.

BeforeAll {
    $ParentPath = Split-Path -Path $PSScriptRoot -Parent
    $PrivatePath = Join-Path $ParentPath -ChildPath "src\Lib\Functions\Private"
    $Script:SourceRoot = Join-Path $ParentPath -ChildPath "src"

    . (Join-Path $PrivatePath -ChildPath "Write-LogOutput.ps1")
    . (Join-Path $PrivatePath -ChildPath "Protect-LogMessage.ps1")
    . (Join-Path $PrivatePath -ChildPath "ConvertTo-RedactedLogString.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-LogResultShape.ps1")
    . (Join-Path $PrivatePath -ChildPath "Test-LogLevelThreshold.ps1")
    . (Join-Path $PrivatePath -ChildPath "Get-SessionLogFileName.ps1")
    . (Join-Path $PrivatePath -ChildPath "Write-SessionLogFile.ps1")

    $Script:Tracer = [System.Diagnostics.Trace]
    $Script:WriteLogOutputPath = Join-Path $PrivatePath -ChildPath "Write-LogOutput.ps1"
    $Script:WriteLogOutputSource = Get-Content $Script:WriteLogOutputPath -Raw

    # The secret material issue #39's acceptance criteria name, plus the query text of #111.
    $Script:SecretPassword = "Sup3rSecret!"
    $Script:SecretBasicHeader = "b21hZGE6U3VwM3JTZWNyZXQh"
    $Script:SecretJwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJvbWFkYSJ9.c2lnbmF0dXJldmFsdWU"
    $Script:SecretSessionId = "sessionvalue1234"

    function Open-TestSessionLogFile {
        param([string]$LogLevel = "DEBUG")

        $Folder = Join-Path ([System.IO.Path]::GetTempPath()) -ChildPath ("OmadaSqlLogGate_{0}" -f ([guid]::NewGuid().ToString("N")))
        New-Item -Path $Folder -ItemType Directory -Force | Out-Null

        $State = New-SessionLogFileState -LogLevel $LogLevel
        $State.Directory = $Folder
        $State.MaxBytes = [long]20 * 1MB
        $State.Path = Join-Path $Folder -ChildPath (Get-SessionLogFileName -StartTime $State.StartTime -ProcessId $State.ProcessId -Part $State.Part)
        $State.Writer = Open-SessionLogFileWriter -Path $State.Path
        $State.Pending = $null
        $Script:SessionLogFile = $State

        return $State
    }

    function Read-SessionLogFileWhileOpen {
        param([string]$Path)

        $Stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        try {
            $Reader = [System.IO.StreamReader]::new($Stream)
            try {
                return $Reader.ReadToEnd()
            }
            finally {
                $Reader.Dispose()
            }
        }
        finally {
            $Stream.Dispose()
        }
    }
}

Describe "The session log file sits behind Protect-LogMessage" {

    Context "Who is allowed to call the writer" {

        It "is called from exactly two files in the whole source tree, and no others" {
            # Anything else is a second route to disk, and a second route is a route around the gate.
            # Only the file that defines the writer is excluded from the scan - excluding a CALLER
            # would be a hole in exactly the guard this suite exists to be, so Start-SessionLogFile
            # is listed here and pinned down by the test below rather than waved through.
            $CallingFile = Get-ChildItem -Path $Script:SourceRoot -Filter "*.ps1" -Recurse -File |
                Where-Object { $_.Name -ne "Write-SessionLogFile.ps1" } |
                Where-Object { (Get-Content $_.FullName -Raw) -match "Write-SessionLogFile\s+-Line" } |
                ForEach-Object { $_.Name } | Sort-Object

            @($CallingFile) | Should -Be @("Start-SessionLogFile.ps1", "Write-LogOutput.ps1")
        }

        It "is called by Write-LogOutput exactly once" {
            ([regex]::Matches($Script:WriteLogOutputSource, "Write-SessionLogFile -Line")).Count | Should -Be 1
        }

        It "is called by Start-SessionLogFile exactly once, and only to replay already-gated lines" {
            # The second caller is safe for one reason only: it replays entries the buffer holds,
            # and every entry in that buffer arrived through Write-LogOutput and therefore through
            # Protect-LogMessage. A call here passing anything else - a raw message, a status line
            # composed on the spot - would be a message reaching disk unmasked.
            $StartSource = Get-Content (Join-Path $Script:SourceRoot -ChildPath "Lib\Functions\Private\Start-SessionLogFile.ps1") -Raw

            ([regex]::Matches($StartSource, "Write-SessionLogFile\s+-Line")).Count | Should -Be 1
            $StartSource | Should -Match 'Write-SessionLogFile -Line \$Entry\.Line -LogType \$Entry\.LogType'
        }
    }

    Context "Where in Write-LogOutput it is called" {

        It "masks the message before the file writer is anywhere near it" {
            $GateIndex = $Script:WriteLogOutputSource.IndexOf('$Message = Protect-LogMessage -Message $Message')
            $WriterIndex = $Script:WriteLogOutputSource.IndexOf('Write-SessionLogFile')

            $GateIndex | Should -BeGreaterThan -1
            $WriterIndex | Should -BeGreaterThan -1
            $WriterIndex | Should -BeGreaterThan $GateIndex
        }

        It "hands the writer the same text the log window gets, not the raw message" {
            # $Message is the unmasked parameter until the gate reassigns it; $LogMessage.Text is
            # what the gate's output was formatted into. Passing $Message here would be the leak.
            $Script:WriteLogOutputSource | Should -Match 'Write-SessionLogFile -Line \(\(\$LogMessage\.Text\) -join'
        }
    }

    Context "The writer does no redaction of its own" {

        It "never calls Protect-LogMessage, because by then it is already too late to matter" {
            # Not an optimisation: a writer that redacted its own input would be a second, parallel
            # redaction decision - which is precisely the "beside, not behind" structure the issue
            # forbids, because the two would drift.
            $WriterSource = Get-Content (Join-Path $Script:SourceRoot -ChildPath "Lib\Functions\Private\Write-SessionLogFile.ps1") -Raw

            # An invocation, not a mention: the file's own notes explain why the rule exists, and a
            # test that banned the words would only teach people to stop writing the notes.
            $WriterSource | Should -Not -Match "Protect-LogMessage\s+-"
            $WriterSource | Should -Not -Match "\|\s*Protect-LogMessage"
        }
    }
}

Describe "What actually reaches the file" {

    BeforeEach {
        $Script:RunTimeConfig = [PSCustomObject]@{
            ApplicationName     = "Test"
            VerboseParameterSet = $true
            Logging             = [PSCustomObject]@{
                LogLevelSetting = "VERBOSE2"
                LogToConsole    = $false
                AppLogObject    = [System.Collections.ObjectModel.ObservableCollection[string]]::new()
            }
        }
        $Script:Tabs = @()
        $Script:ActiveTabId = $null
        $Script:TextBoxLog = $null
        $Script:SkipBodyRedaction = $false
        $Script:SessionLogFile = $null
    }

    AfterEach {
        $Folder = $Script:SessionLogFile.Directory
        Stop-SessionLogFile
        if (![string]::IsNullOrWhiteSpace($Folder)) {
            Remove-Item -Path $Folder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Secrets in free-form text" {

        It "masks a Basic authorization header on disk" {
            $State = Open-TestSessionLogFile

            "Request failed. Authorization: Basic {0}" -f $Script:SecretBasicHeader | Write-LogOutput -LogType LOG -SkipDialog

            $Content = Read-SessionLogFileWhileOpen -Path $State.Path
            $Content | Should -Match "Request failed"
            $Content | Should -Not -Match $Script:SecretBasicHeader
        }

        It "masks a bare JWT on disk" {
            $State = Open-TestSessionLogFile

            "Cached token: {0}" -f $Script:SecretJwt | Write-LogOutput -LogType LOG -SkipDialog

            (Read-SessionLogFileWhileOpen -Path $State.Path) | Should -Not -Match ([regex]::Escape($Script:SecretJwt))
        }

        It "masks a session cookie on disk" {
            $State = Open-TestSessionLogFile

            "Set-Cookie: ASP.NET_SessionId={0}; path=/" -f $Script:SecretSessionId | Write-LogOutput -LogType LOG -SkipDialog

            (Read-SessionLogFileWhileOpen -Path $State.Path) | Should -Not -Match $Script:SecretSessionId
        }

        It "masks a full request parameter set on disk, end to end through both redaction layers" {
            $State = Open-TestSessionLogFile -LogLevel "VERBOSE"
            $Credential = [PSCredential]::new("omada\svc_sql", (ConvertTo-SecureString $Script:SecretPassword -AsPlainText -Force))
            $RequestParameters = @{
                Uri                = "https://tenant.omada.cloud/OData/BuiltIn/C_P_SQLTROUBLESHOOTING"
                Method             = "POST"
                AuthenticationType = "Basic"
                Credential         = $Credential
                Headers            = @{ Authorization = "Basic {0}" -f $Script:SecretBasicHeader }
                Body               = @{ query = "SELECT * FROM dbo.Identity"; page = 1 }
            }

            "Parameters: {0}" -f (ConvertTo-RedactedLogString -InputObject $RequestParameters) | Write-LogOutput -LogType VERBOSE -SkipDialog

            $Content = Read-SessionLogFileWhileOpen -Path $State.Path
            $Content | Should -Match "Parameters:"
            $Content | Should -Not -Match $Script:SecretBasicHeader
            $Content | Should -Not -Match ([regex]::Escape($Script:SecretPassword))
            $Content | Should -Not -Match "SELECT"
            $Content | Should -Match "tenant.omada.cloud"
        }

        It "writes exactly what the log window shows, one gate and one text" {
            $State = Open-TestSessionLogFile

            "Request failed. Authorization: Basic {0}" -f $Script:SecretBasicHeader | Write-LogOutput -LogType LOG -SkipDialog

            $Window = ($Script:RunTimeConfig.Logging.AppLogObject -join "`r`n").Trim()
            (Read-SessionLogFileWhileOpen -Path $State.Path).Trim() | Should -BeExactly $Window
        }
    }

    Context "The request body option of issue #62" {

        It "puts the query text on disk when the user has asked for it, exactly as it puts it in the window" {
            # Stated as a test because it is a deliberate decision, not an oversight. "Show request
            # body" lifts the body rule inside ConvertTo-RedactedLogString, which is upstream of the
            # one gate both the window and the file are behind - so the file agrees with the window
            # by construction. Diverging would mean a second redaction decision applied only to the
            # file, which is the structure this whole issue forbids.
            $State = Open-TestSessionLogFile -LogLevel "VERBOSE"
            $Script:SkipBodyRedaction = $true

            "Body: {0}" -f (ConvertTo-RedactedLogString -InputObject @{ query = "SELECT * FROM dbo.Identity" } -ShapeOnly) | Write-LogOutput -LogType VERBOSE -SkipDialog

            $Content = Read-SessionLogFileWhileOpen -Path $State.Path
            $Content | Should -Match "SELECT \* FROM dbo.Identity"
            ($Script:RunTimeConfig.Logging.AppLogObject -join "`r`n") | Should -Match "SELECT \* FROM dbo.Identity"
        }

        It "keeps the query text off disk when the user has not" {
            $State = Open-TestSessionLogFile -LogLevel "VERBOSE"
            $Script:SkipBodyRedaction = $false

            "Body: {0}" -f (ConvertTo-RedactedLogString -InputObject @{ query = "SELECT * FROM dbo.Identity" } -ShapeOnly) | Write-LogOutput -LogType VERBOSE -SkipDialog

            (Read-SessionLogFileWhileOpen -Path $State.Path) | Should -Not -Match "SELECT"
        }
    }

    Context "Independent of the log window" {

        It "keeps the session when the log window is cleared" {
            # Open-LogForm's TextChanged handler calls AppLogObject.Clear(), which used to destroy
            # the only copy there was.
            $State = Open-TestSessionLogFile
            "something worth keeping" | Write-LogOutput -LogType LOG -SkipDialog

            $Script:RunTimeConfig.Logging.AppLogObject.Clear()

            $Script:RunTimeConfig.Logging.AppLogObject.Count | Should -Be 0
            (Read-SessionLogFileWhileOpen -Path $State.Path) | Should -Match "something worth keeping"
        }

        It "records at its own level what the window is too quiet to show" {
            # The window at its shipped default, the file at DEBUG: the detail that removes the
            # "please reproduce it with -LogLevel VERBOSE" round trip is already on disk.
            $State = Open-TestSessionLogFile -LogLevel "DEBUG"
            $Script:RunTimeConfig.Logging.LogLevelSetting = "WARNING"

            "a detail the window never showed" | Write-LogOutput -LogType DEBUG -SkipDialog

            ($Script:RunTimeConfig.Logging.AppLogObject -join "`r`n") | Should -Not -Match "a detail the window never showed"
            (Read-SessionLogFileWhileOpen -Path $State.Path) | Should -Match "a detail the window never showed"
        }

        It "does not write what is below the file's own level either" {
            $State = Open-TestSessionLogFile -LogLevel "WARNING"

            "a detail nobody asked for" | Write-LogOutput -LogType DEBUG -SkipDialog

            (Read-SessionLogFileWhileOpen -Path $State.Path) | Should -Not -Match "a detail nobody asked for"
        }
    }

    Context "When there is no file" {

        It "logs to the window exactly as it always did" {
            $Script:SessionLogFile = $null

            "an ordinary line" | Write-LogOutput -LogType INFO -SkipDialog

            ($Script:RunTimeConfig.Logging.AppLogObject -join "`r`n") | Should -Match "an ordinary line"
        }
    }
}
