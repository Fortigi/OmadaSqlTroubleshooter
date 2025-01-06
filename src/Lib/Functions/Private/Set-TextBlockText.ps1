function Set-TextBlockText {
    PARAM(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $TextBlockObject,
        [Parameter(Mandatory = $false)]
        [string]$Text
    )

    try {
        $CurrentButtonContent = $TextBlockObject.Text
        if ([string]::IsNullOrEmpty($Text)) {
                $TextBlockObject.Text = $null
            }
            else {
                $TextBlockObject.Text = $Text
            }
            $TextBlockObject.Text = $Text
            "{0} set from '{1}' to '{2}'" -f $TextBlockObject.Name, $CurrentButtonContent, $TextBlockObject.Text | Write-LogOutput -LogType DEBUG

        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }


    }
