function Get-SessionKeepAliveInterval {
    <#
    .SYNOPSIS
    How often to refresh a tenant session, in minutes. Zero means do not.

    .DESCRIPTION
    Configurable rather than hardcoded because the number it has to stay under - how long an Omada
    session lives - is an estimate. Roughly ten minutes is what was observed; it is not documented
    and it may differ per tenant. A setting means a wrong guess can be corrected without a release.

    The default is five minutes: comfortably inside the estimate, and cheap. One $top=1 GET per
    connected tenant per five minutes is a rounding error next to a query.

    Zero switches the keep-alive off entirely, for anyone who would rather this application did not
    touch the tenant on a timer. One knob rather than two - a separate "enabled" flag could disagree
    with the interval, and then someone has to decide which wins.

    Anything unusable - absent, negative, not a number, or the -1 that an Int property carries when
    it has no stored value - falls back to the schema default rather than to zero. Falling back to
    zero would silently disable a feature the user never asked to disable.

    .OUTPUTS
    [int] minutes between refreshes, or 0 when disabled.
    #>
    [CmdLetBinding()]
    [OutputType([int])]
    param()

    $Private:Default = 5
    try {
        $Private:SchemaDefault = Get-ConfigSchemaDefault -Property "SessionKeepAliveMinutes"
        if ($null -ne $Private:SchemaDefault -and [int]$Private:SchemaDefault -ge 0) {
            $Private:Default = [int]$Private:SchemaDefault
        }
    }
    catch {
        # The literal above is the fallback of last resort, for a schema that cannot be read.
    }

    if ($null -eq $Script:AppGlobalConfig -or $null -eq $Script:AppGlobalConfig.SessionKeepAliveMinutes) {
        return $Private:Default
    }

    $Private:Stored = 0
    if (-not [int]::TryParse([string]$Script:AppGlobalConfig.SessionKeepAliveMinutes, [ref]$Private:Stored)) {
        return $Private:Default
    }

    # Zero is a real answer - "off" - so only a negative value is treated as absent.
    if ($Private:Stored -lt 0) {
        return $Private:Default
    }

    return $Private:Stored
}
