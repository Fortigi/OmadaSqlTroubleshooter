$Script:RootDir = (Get-Item $PSScriptRoot).Parent.FullName
$ErrorActionPreference = "Stop"

Deploy 'Deploy dummy' {

      By Filesystem Config {
        FromSource ""
        To ""
        WithPostScript {
        }
        WithOptions @{
            Mirror = $true
        }
        Tagged All
    }
}
