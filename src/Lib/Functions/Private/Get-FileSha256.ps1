function Get-FileSha256 {
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true)]
        [string]$Path
    )

    # Hashed through .NET rather than Get-FileHash on purpose: Get-FileHash lives in
    # Microsoft.PowerShell.Utility, and the integrity check must not become unavailable because a
    # module directory on the machine shadows that one. Returns lower-case hex, matching the lock.
    #
    # No tracer preamble: see Get-DependencyLock. This runs during module import.

    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $Stream = [System.IO.File]::OpenRead($Path)
        try {
            return ([System.BitConverter]::ToString($Sha256.ComputeHash($Stream)) -replace "-", "").ToLowerInvariant()
        }
        finally {
            $Stream.Dispose()
        }
    }
    finally {
        $Sha256.Dispose()
    }
}
