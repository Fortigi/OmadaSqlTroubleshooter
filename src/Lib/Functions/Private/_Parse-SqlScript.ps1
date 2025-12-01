# Function to parse SQL script for variables, CTEs, and the main query
function Test-SqlScript {
    [CmdLetBinding()]
    param(
        [string]$SqlScript
    )

    $ParsedResult = @{ Variables = @{}; CTEs = @(); MainQuery = "" }

    $Lines = $SqlScript -split "`n"

    $VariableSection = $true
    $CTESection = $false
    $MainQuerySection = $false

    $CurrentCTE = $null
    $CTEContent = @()

    foreach ($Line in $Lines) {
        $StrippedLine = $Line.Trim()

        if ($StrippedLine -match "^DECLARE") {
            if (-not $VariableSection) {
                throw "DECLARE found after variables section ended."
            }

            if ($StrippedLine -match "@([a-zA-Z0-9_]+)") {
                $VariableName = $matches[1]
                $ParsedResult.Variables[$VariableName] = $null
            }
        }
        elseif ($StrippedLine -match "^WITH" -or $StrippedLine -match "^#") {
            $VariableSection = $false
            $CTESection = $true

            if ($StrippedLine -match "^WITH ([a-zA-Z0-9_]+)") {
                $CurrentCTE = $matches[1]
                $CTEContent = @()
            }
            elseif ($StrippedLine -match "^#([a-zA-Z0-9_]+)") {
                $CurrentCTE = $matches[1]
                $CTEContent = @()
            }
        }
        elseif ($CurrentCTE -and ($StrippedLine -match "^\)" -or $StrippedLine -match "SELECT")) {
            $CTEContent += $StrippedLine
            $ParsedResult.CTEs.$CurrentCTE = $CTEContent -join " `n"
            $CurrentCTE = $null
            $CTEContent = @()
        }
        elseif ($CTESection -and $CurrentCTE) {
            $CTEContent += $StrippedLine
        }
        elseif ($StrippedLine -match "^SELECT") {
            $VariableSection = $false
            $CTESection = $false
            $MainQuerySection = $true

            $ParsedResult.MainQuery += $StrippedLine + " `n"
        }
        elseif ($MainQuerySection) {
            $ParsedResult.MainQuery += $StrippedLine + " `n"
        }
    }

    return $ParsedResult
}
