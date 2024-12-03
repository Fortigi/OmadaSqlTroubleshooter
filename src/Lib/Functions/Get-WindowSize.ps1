function Get-WindowSize {

    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Form,
        [switch]$AsString
    )
    try {
        if ($AsString) {
            return "{0}x{1}" -f $Form.Width, $Form.Height
        }
        else {
            return [PSCustomObject]@{
                Width  = $Form.Width
                Height = $Form.Height
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
