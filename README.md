# Omada Sql Troubleshooter
[![PSGallery Version](https://img.shields.io/powershellgallery/v/OmadaSqlTroubleshooter.svg?style=flat&logo=powershell&label=PSGallery%20Version)](https://www.powershellgallery.com/packages/OmadaSqlTroubleshooter) [![PSGallery Downloads](https://img.shields.io/powershellgallery/dt/OmadaSqlTroubleshooter.svg?style=flat&logo=powershell&label=PSGallery%20Downloads)](https://www.powershellgallery.com/packages/OmadaSqlTroubleshooter) [![PowerShell](https://img.shields.io/badge/PowerShell-7-darkblue?style=flat&logo=powershell)](https://www.powershellgallery.com/packages/OmadaSqlTroubleshooter) [![PSGallery Platform](https://img.shields.io/powershellgallery/p/OmadaSqlTroubleshooter.svg?style=flat&logo=powershell&label=PSGallery%20Platform)](https://www.powershellgallery.com/packages/OmadaSqlTroubleshooter)

## DESCRIPTION

OmadaSqlTroubleshooter is a PowerShell Module that contains an interactive desktop application that is used to manage and execute SQL queries stored in the SQL Troubleshooting section in Omada Identity Suite.

![OmadaSQLTroubleshooter Overview](./images/overview.png)

### Features

#### Query Management
- Create, update, save and execute SQL queries
- Save queries without executing
- Query history
  - Browse history
  - Restore a query from history
  - Compare changes for each updated query
  - Export historic queries (JSON, CSV, TXT)

#### Editor & IntelliSense
- Basic IntelliSense for SQL, tables and columns
- Schema view — press **Shift + click** on a table or column to insert it into the editor
- Filter queries while typing in the editor

#### Results & Export
- View results in a PowerShell GridView
- Context menu for quick copy, select all and save
- Select cells, columns, rows and copy to clipboard
- Export results to JSON, CSV, PowerShell CliXml or plain text

#### Authentication
- **WebView2** — browser-based via WebView2 (default)
- **Browser** — browser-based via Selenium
- **OAuth** — OAuth2 / Entra ID

#### Tabs & Multiple Connections
- Work with multiple queries and connections side by side, each in its own tab
- Every tab is an independent workspace with its own connection settings, query editor and results
- **Add a tab** — click the **+** button next to the tabs, or use the tab **New Tab** context menu
- **Duplicate a tab** — copy a tab's connection and query into a new, unsaved tab (**Duplicate Tab**), or copy only the connection without the query (**Duplicate Tab without Query**)
- **Close tabs** — close a single tab (its **✕** button or context menu), **Close All But This**, or **Close All**
- **Reorder tabs** — drag a tab to a new position
- Tabs shrink to fit on a single row; long names are truncated with an ellipsis (…)
- New and duplicated tabs are auto-named `Query{#}`, kept unique against your saved queries; the name is pre-filled into the Display name field so a duplicate can be saved with a single click
- A query Display name cannot be empty when saving

##### Shared connections (connection pools)
Tabs that share the same connection form a **connection pool**, identified by the combination of **tenant URL + authentication method + credentials**:
- When a tab connects, every tab in the same pool shares that active connection — no repeated sign-in
- Disconnecting one tab disconnects only that tab; the others in the pool stay connected
- A new tab whose connection settings match an already-connected pool reuses that pool's connection
- A new tab whose settings match no connected pool creates a new pool of its own

#### Connectivity & State
- Auto-complete connection URL (e.g. `tenantname` → `https://tenantname.omada.cloud`)
- Select query or connection from a dropdown while typing
- Automatic persistence of connections, queries, tabs and layout between sessions
- Option to store credentials; WebView2/Browser with Entra ID can auto-fill them
- Detailed logging to log window and console

#### Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `F5` | Execute query |
| `Enter` (in connection field) | Initiate connection |
| `Ctrl + S` | Save current query in Omada |
| `Ctrl + Shift + K` | Duplicate the current tab (connection and query) |
| `Ctrl + T` | Duplicate the current tab without the query editor contents |
| `Ctrl + W` / `Ctrl + F4` | Close the current tab |
| `Ctrl + Tab` | Switch to the next tab (wraps from the last tab to the first) |
| `Ctrl + Shift + Tab` | Switch to the previous tab (wraps from the first tab to the last) |
| `Ctrl + C` (result pane) | Copy selected cell(s) to clipboard |
| `Ctrl + Shift + C` (result pane) | Copy selected cell(s) including headers to clipboard |
| `Ctrl + Shift + S` (result pane) | Copy selected cell(s) formatted as array for direct use in a Sql query to clipboard |
| `Ctrl + Shift + P` (result pane) | Copy selected cell(s) formatted as array for direct use in a PowerShell query to clipboard |

This application leverages the permissions of the user that is logged in. The application uses the built-in OData endpoint (C_P_SQLTROUBLESHOOTING) for the SQL Troubleshooter and the Omada Enterprise Server API.

> [!IMPORTANT]
> The C_P_SQLTROUBLESHOOTING OData endpoint is disabled by default. Enabled it in the Data Object Type configuration in Omada in order to use this application. Also make sure that you have the correct user permissions to Create, Read and Modify objects via OData.

> [!IMPORTANT]
> Authentication is handled by the OmadaWeb.PS PowerShell module. This module must be installed before running the application. OmadaWeb.PS can simply be installed using this command:
> ```powershell
> Install-Module -Name OmadaWeb.PS
> ```

## INSTALLATION

To install the module from the PowerShell Gallery, you can use the following command:

```powershell
Install-Module -Name OmadaSqlTroubleshooter
```

## USAGE

### Requirements

This module requires:
- Windows operating system;
- PowerShell 7;
- [OmadaWeb.PS PowerShell Module](https://www.powershellgallery.com/packages/omadaweb.ps) (Version 2026.07.09.9 or higher);
- [Microsoft Edge WebView2](https://developer.microsoft.com/en-us/microsoft-edge/webview2);
- Omada Identity Cloud with OData enabled for the C_P_SQLTROUBLESHOOTING data object type;
- Create, Read and Modify user permissions for OData.

> [!NOTE]
> If you are not able to install Microsoft Edge Webview2 you can download the Fixed Version x64 bit from [here](https://developer.microsoft.com/en-us/microsoft-edge/webview2). Extract the Cab file using e.g. 7-Zip, copy the contents from folder ```'Microsoft.WebView2.FixedVersionRuntime.xxxx.x64'``` to ```%LOCALAPPDATA%\OmadaSqlTroubleshooter\bin\Webview2Runtime```. The contents of the target folder should now like as shown in the image below.
> <br><img src="./images/webview2.png" width="300" height="300" alt="Webview2Runtime folder"><br>

### Importing the Module

To import the module, use the following command:

```powershell
Import-Module OmadaSqlTroubleshooter
```

## SYNTAX

### Invoke-OmadaSqlTroubleshooter

```powershell
Invoke-OmadaSqlTroubleshooter [[-LogLevel] <string>] [-Reset] [-LogToConsole] [<CommonParameters>]
```

## EXAMPLES

Here are some example commands you can use with the OmadaSqlTroubleshooter module:

### Example 1: Start OmadaSqlTroubleshooter.
```powershell
Invoke-OmadaSqlTroubleshooter
```

### Example 2: Start OmadaSqlTroubleshooter with LogLevel Debug and log output to console
```powershell
Invoke-OmadaSqlTroubleshooter -LogLevel DEBUG -LogToConsole
```

### Example 3: Reset OmadaSqlTroubleshooter
```powershell
Invoke-OmadaSqlTroubleshooter -Reset
```

## PARAMETERS

### -LogLevel
Set the loglevel. Default is INFO

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: INFO, DEBUG, VERBOSE, WARNING, ERROR, FATAL, VERBOSE2

Required: False
Position: 0
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -LogToConsole
Outputs logging to the console.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -UseWebView2Auth
Uses the WebView2 for browser-based authentication instead of Selenium.

> [!IMPORTANT]
> This parameter is deprecated, select the WebView2 authentication option from the UI instead.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -NoReconnect
Prevents the application from attempting to reconnect to the Omada Identity Suite using the stored connection information.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Reset
Resets the stored configuration to default.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None

## OUTPUTS

### None

## NOTES

### None

## KNOWN ISSUES

> [!NOTE]
> **Queries that return no rows and queries that fail show the same warning.**
> The message _"Warning: Query did not return any results!"_ is displayed in both cases.
> This is a limitation of the SQL Troubleshooter component in Omada Identity Suite,
> which does not distinguish between an empty result set and a query execution failure.

## CONTRIBUTING

Contributions are welcome! If you have ideas for improvements or bug fixes, feel free to open a pull request on [GitHub](https://github.com/Fortigi/OmadaSqlTroubleshooter).

## RELATED LINKS

[`OmadaWeb.PS`](https://github.com/Fortigi/OmadaWeb.PS)

['Omada Documentation'](https://documentation.omadaidentity.com/)
## LICENSE

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
