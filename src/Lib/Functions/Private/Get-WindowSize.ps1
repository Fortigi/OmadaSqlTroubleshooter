function Get-WindowSize {
    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Form,
        [switch]$AsString
    )
    try {
        "{0}: {1}x{2} AsString: {3}" -f $Form.Name, $Form.Width , $Form.Height, $AsString.IsPresent | Write-LogOutput -LogType VERBOSE2
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
