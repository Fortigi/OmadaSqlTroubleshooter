
function Test-Variable {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ExcludeVariable', Justification = 'The variable is used, but script analyzer does not recognize it')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ExcludeAttribute', Justification = 'The variable is used, but script analyzer does not recognize it')]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$Expression,
        [switch]$ExcludeVariable,
        [switch]$ExcludeAttribute
    )

    function ReturnObject {
        if ($ExcludeVariable -and $ExcludeAttribute) {
            $Return = $false
        }
        elseif ($ExcludeAttribute -and !$ExcludeVariable) {
            $Return.Remove("AttributeExists")
            $Return = $Return.VariableExists
        }
        elseif ($ExcludeVariable -and !$ExcludeAttribute) {
            $Return.Remove("VariableExists")
            $Return = $Return.AttributeExists
        }
        return $Return
    }

    $Parts = $Expression.TrimStart('$').Trim() -split '\.'

    $Root = $Parts[0]

    $ScopePrefix = ''
    if ($Root -match '^(\w+:)') {
        $ScopePrefix = $Matches[1]
        $Root = $Root.Substring($ScopePrefix.Length)
    }

    $SessionState = $ExecutionContext.SessionState
    $Variable = $SessionState.PSVariable.Get($Root)

    $Return = @{
        VariableExists  = $false
        AttributeExists = $false
    }

    if ($null -eq $Variable) {
        $Return.VariableExists = $false
        return ReturnObject
    }

    $CurrentObject = $Variable.Value
    if (($Parts | Measure-Object).Count -eq 1) {
        return ReturnObject
    }
    foreach ($Part in $Parts[1..($Parts.Count - 1)]) {
        if ($null -eq $CurrentObject) {
            $Return.VariableExists = $true
            return ReturnObject
        }

        if ($CurrentObject -is [hashtable]) {
            $Member = $CurrentObject.keys | Where-Object {$_ -eq $Part}
        }
        else {
            $Member = $CurrentObject | Get-Member  -Name $Part -Force -ErrorAction SilentlyContinue | Where-Object {$_.MemberType -in @("Property", "Field", "Method")}
        }

        if ($null -eq $Member) {
            $Return.VariableExists = $true
            return ReturnObject
        }
        $CurrentObject = $CurrentObject.$Part
    }
    return ReturnObject
}
