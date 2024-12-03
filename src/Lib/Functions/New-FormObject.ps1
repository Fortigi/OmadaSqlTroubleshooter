function New-FormObject {

    param (
        [parameter(Mandatory = $False)]
        [validateScript({ Test-Path $_ -PathType Leaf })]
        $FormPath,
        [parameter(Mandatory = $False)]
        $Xaml
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
        $Form.Icon = Get-Icon -Type Wpf

        # Access controls
        $Elements = @()
        $ElementNames = @("ComboBox", "Label", "TextBox", "Button", "CheckBox", "RadioButton", "PasswordBox", "ComboBoxItem", "WebView2", "DataGrid", "TextBlock", "TreeViewSqlSchema")
        foreach ($ElementName in $ElementNames) {
            $Xaml.DocumentElement.SelectNodes("//default:$ElementName", $NamespaceManager) | ForEach-Object {
                $_.Name | Select-Object -Unique | ForEach-Object {
                    if (![string]::IsNullOrWhiteSpace($_) -and $null -ne $Form.FindName($_)) {
                        $Elements += @{
                            "$_" = $Form.FindName($_)
                        }
                    }
                }
            }
        }

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
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
