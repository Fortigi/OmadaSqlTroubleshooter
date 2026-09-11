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
            $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
        }
    })
