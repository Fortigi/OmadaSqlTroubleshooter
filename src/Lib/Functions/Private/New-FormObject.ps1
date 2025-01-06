function New-FormObject {
PARAM (
        [parameter(Mandatory = $False)]
        [validateScript({ Test-Path $_ -PathType Leaf })]
        $FormPath,
        [parameter(Mandatory = $False)]
        $Xaml,
        [parameter(Mandatory = $False)]
        $ParentForm
    )
    try {
        if ($null -eq $FormPath -and $null -eq $Xaml) {
            "Either FormPath or Xaml must be provided!" | Write-LogOutput -LogType ERROR
            break
        }

        if ($null -ne $FormPath) {
            [xml]$Xaml = Get-Content $FormPath -Raw
        }

        $NamespaceManager = New-Object System.Xml.XmlNamespaceManager($Xaml.NameTable)
        $NamespaceManager.AddNamespace("default", "http://schemas.microsoft.com/winfx/2006/xaml/presentation")
        $NamespaceManager.AddNamespace("x", "http://schemas.microsoft.com/winfx/2006/xaml")
        $NamespaceManager.AddNamespace("Wpf", "clr-namespace:Microsoft.Web.WebView2.Wpf;assembly=Microsoft.Web.WebView2.Wpf")

        $Reader = (New-Object System.Xml.XmlNodeReader $Xaml)
        $Form = [Windows.Markup.XamlReader]::Load($Reader)
        "Create form: {0}" -f $Form.Name | Write-LogOutput -LogType DEBUG
        $Form.Icon = Get-Icon -Type Wpf

        # Access controls
        $Elements = @()
        $ElementNames = @("ComboBox", "Label", "TextBox", "Button", "CheckBox", "RadioButton", "PasswordBox", "ComboBoxItem", "WebView2", "DataGrid", "TextBlock", "TreeViewSqlSchema")
        foreach ($ElementName in $ElementNames) {
            "Find element type: {0}" -f $ElementName | Write-LogOutput -LogType DEBUG
            $Xaml.DocumentElement.SelectNodes("//default:$ElementName", $NamespaceManager) | ForEach-Object {
                $_.Name | Select-Object -Unique | ForEach-Object {
                    if (![string]::IsNullOrWhiteSpace($_) -and $null -ne $Form.FindName($_)) {
                        "Add element type: {0}" -f $_ | Write-LogOutput -LogType DEBUG
                        $Elements += @{
                            "$_" = $Form.FindName($_)
                        }
                    }
                }
            }
        }

        if ($null -ne $ParentForm) {
            "Parent form: {0}" -f $ParentForm.Name | Write-LogOutput -LogType DEBUG
            $Form.Owner = $ParentForm
            "Form Height: {0}" -f $Form.Height | Write-LogOutput -LogType DEBUG
            "Parent form Height: {0}" -f $ParentForm.Height | Write-LogOutput -LogType DEBUG
            if([double]::IsNaN($Form.Height)){
                $Form.Height = $ParentForm.Height
            }
            else{
                $Form.Height = [math]::Max($Form.Height, $ParentForm.Height)
            }
            if($Form.Width -eq "NaN"){
                $Form.Width = $Form.MinWidth
            }
        }

        "Form Dimensions: {0}x{1}" -f  $Form.Width,$Form.Height | Write-LogOutput -LogType DEBUG
        "Form Location: {0}x{1}" -f $Form.Left, $Form.Top | Write-LogOutput -LogType DEBUG

        "Return form object for: {0}" -f $Form.Name | Write-LogOutput -LogType DEBUG

        return [PSCustomObject]@{
            Definition = $Form
            Elements   = $Elements
            Xaml       = $Xaml
            Position   = [PSCustomObject]@{
                Left = $null
                Top  = $null
            }
            Size       = [PSCustomObject]@{
                Width  = $Form.MinWidth
                Height = $Form.MinHeight
            }
            State      = "NotOpenend"
            PositionManager = @{
                Synchronizing       = $false
                PositionOffSetLeft  = 0
                PositionOffSetRight = 0
                PositionOffSetTop   = 0
                MainWindowRight     = 0
                MainWindowBottom    = 0
                ChildWindowLeft     = 0
                ChildWindowRight    = 0
                ChildWindowBottom   = 0
                LastPositionChange  = Get-Date
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
