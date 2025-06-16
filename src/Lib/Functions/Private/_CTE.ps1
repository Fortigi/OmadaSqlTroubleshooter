#https://secretsql.wordpress.com/tag/powershell/

Invoke-RestMethod "https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SqlLocalDB.msi" -OutFile "$env:temp\SqlLocalDB.msi"

Add-Type -Path "C:\Users\mark\Downloads\microsoft.sqlserver.transactsql.scriptdom.170.12.0\lib\net8.0\Microsoft.SqlServer.TransactSql.ScriptDom.dll" -PassThru

$SqlQuery = Get-Content "sql.sql" -Raw

$parser = New-Object Microsoft.SqlServer.TransactSql.ScriptDom.TSql150Parser($true)

$stringReader = [System.IO.StringReader]::new($SqlQuery)
$parseErrors = New-Object System.Collections.Generic.List[Microsoft.SqlServer.TransactSql.ScriptDom.ParseError]

$fragment = $parser.Parse($stringReader, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    foreach ($parseErr in $parseErrors) {
        Write-Host "PARSE ERROR: Line: $($parseErr.line) offset: $($parseErr.offset) message:  $($parseErr.message) "  -ForegroundColor yellow
    }
}

#ExpressionName
$fragment.batches.statements.WithCtesAndXmlNamespaces.CommonTableExpressions[0].ExpressionName.Value


#Get CTE query
$fragment.batches.statements.WithCtesAndXmlNamespaces.CommonTableExpressions[0].QueryExpression.ScriptTokenStream[($fragment.batches.statements.WithCtesAndXmlNamespaces.CommonTableExpressions[0].QueryExpression.FirstTokenIndex)..($fragment.batches.statements.WithCtesAndXmlNamespaces.CommonTableExpressions[0].QueryExpression.LastTokenIndex)].Text -join ''

#Get Main query
$fragment.batches.statements.queryExpression.ScriptTokenStream[($fragment.batches.statements.queryExpression.FirstTokenIndex)..($fragment.batches.statements.queryExpression.LastTokenIndex)].Text -join ''


# Define LocalDB instance
$InstanceName = "(localdb)\MSSQLLocalDB"
$ConnectionString = "Server=$InstanceName;Integrated Security=True;"

# Create a persistent SQL connection
$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
$SqlConnection.ConnectionString = $ConnectionString
$SqlConnection.Open()

# Create a temporary table
$CreateTempTableQuery = @"
CREATE TABLE #TempTable (
    ID INT,
    Name NVARCHAR(50)
);
INSERT INTO #TempTable VALUES (1, 'John Doe'), (2, 'Jane Smith');
"@
$SqlCommand = $SqlConnection.CreateCommand()
$SqlCommand.CommandText = $CreateTempTableQuery
$SqlCommand.ExecuteNonQuery()

# Query the temporary table
$QueryTempTable = "SELECT * FROM #TempTable;"
$SqlCommand.CommandText = $QueryTempTable
$SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter $SqlCommand
$DataSet = New-Object System.Data.DataSet
$SqlAdapter.Fill($DataSet) | Out-Null

# Display the results
$DataSet.Tables[0] | Format-Table -AutoSize

# Perform more operations (same session)
$InsertQuery = "INSERT INTO #TempTable VALUES (3, 'Alice Johnson');"
$SqlCommand.CommandText = $InsertQuery
$SqlCommand.ExecuteNonQuery()

# Query again
$SqlCommand.CommandText = $QueryTempTable
$SqlAdapter.Fill($DataSet) | Out-Null
$DataSet.Tables[0] | Format-Table -AutoSize

# Close the connection (ends the session and flushes the temporary table)
$SqlConnection.Close()
