function Get-ModuleBaseFolder {
    [CmdletBinding()]
    PARAM()

    "Return Module Base Folder" | Write-LogOutput -LogType VERBOSE
    return Split-Path -Path ($MyInvocation.MyCommand.Module).Path -Parent
}
