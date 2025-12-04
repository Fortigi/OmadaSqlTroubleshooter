function Get-SecureStringFromText {
    <#
	.SYNOPSIS
		Function to convert a secure string to a human readable string.

	.DESCRIPTION

	.EXAMPLE

	.EXAMPLE

	.NOTES
        Mark van Eijken
        Fortigi
#>
    [CmdletBinding()]
    param(
        [PARAMETER(ValueFromPipeline = $true)]
        $SecureString
    )

    begin { }
    process {
        try {
            if ($SecureString) {
                $Private:SecureStringObject = $SecureString | ConvertTo-SecureString
                $Private:BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Private:SecureStringObject)
                $Private:Value = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($Private:BSTR)
                return $Private:Value
            }
            else {
                throw "Get-SecureStringFromText: Parameter 'SecureString' missing!"
            }
        }
        catch {
            throw "Get-SecureStringFromText: Error occured. Is the password file correct? If not, re-run the Set-StoredCredentials Cmdlet"
        }

    }
    end {

    }
}
