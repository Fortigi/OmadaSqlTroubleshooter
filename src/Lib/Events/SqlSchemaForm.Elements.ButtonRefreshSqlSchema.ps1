# The "Refresh schema" action of issue #61 section 2. The schema cache lives for the whole session,
# which is right for a schema that does not change and wrong the moment it does - and a stale cache is
# precisely why the schema validation pass only ever warns. This is the user's way of saying "it
# changed, look again" without restarting the application.
$Script:SqlSchemaForm.Elements.ButtonRefreshSqlSchema.Add_Click({

        param (
            $EventSender,
            $EventArgs
        )

        try {
            $_ | Show-EventInfo

            Reset-SqlSchemaCache
        }
        catch {
            # Write-ContainedErrorLog, not Write-LogOutput -LogType ERROR: the latter ends in
            # Write-Error under $ErrorActionPreference = Stop, so it THROWS. A click handler is
            # invoked by WPF and has no caller worth unwinding to, so an uncontained throw here
            # escapes into the dispatcher's unhandled path and stacks a second dialog on the first.
            # The user still gets the message, exactly once, and control returns normally.
            $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
        }
    })
