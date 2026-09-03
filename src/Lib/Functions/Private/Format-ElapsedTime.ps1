function Format-ElapsedTime {
    <#
    .SYNOPSIS
    Render a duration for the status bar's query-time indicator.

    .DESCRIPTION
    One formatter for every place that writes that indicator, so the live value and the final value
    cannot drift apart. Before this there were three literal renderings of the same field and all
    three used TimeSpan's default format, which produces seven fractional digits - "00:00:03.1234567".
    Six of those digits are noise on a status bar, and the churn is what made a running query look
    jittery rather than smooth.

    Tenths only, which is the precision the indicator is refreshed at (the completion poll timer
    updates it every 100 ms). Whole hours rather than "hh", so a duration past 24 hours keeps counting
    instead of silently rolling over - a query left running overnight should read 26:14:03.0, not
    02:14:03.0.

    .PARAMETER TimeSpan
    The duration to render. A negative value - possible if the system clock moves backwards while a
    request is in flight - is rendered as zero rather than as a negative duration.

    .OUTPUTS
    [string] in the form hh:mm:ss.f - every field fixed-width so the indicator does not shift about as
    it counts, except hours, which is padded to two digits and grows beyond them rather than rolling
    over: a query running for 26 hours reads "26:00:14.0".
    #>
    [CmdLetBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [TimeSpan]$TimeSpan
    )

    if ($TimeSpan.Ticks -lt 0) {
        $TimeSpan = [TimeSpan]::Zero
    }

    return "{0:00}:{1:00}:{2:00}.{3:0}" -f [Math]::Floor($TimeSpan.TotalHours), $TimeSpan.Minutes, $TimeSpan.Seconds, [Math]::Floor($TimeSpan.Milliseconds / 100)
}
