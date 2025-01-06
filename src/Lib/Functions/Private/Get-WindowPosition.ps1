function Get-WindowPosition {
    PARAM(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Form,
        [switch]$AsString
    )

    try {
        if ($AsString) {
            return "{0}x{1}" -f $Form.Left, $Form.Top
        }
        else {
            return [PSCustomObject]@{
                Left = $Form.Left
                Top  = $Form.Top
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
