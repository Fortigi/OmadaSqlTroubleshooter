function Initialize-FormObject {
    [CmdLetBinding()]
    param (
        [parameter(Mandatory = $false)]
        [validateScript({ Test-Path $_ -PathType Leaf })]
        $FormPath,
        [parameter(Mandatory = $false)]
        $Xaml,
        [parameter(Mandatory = $false)]
        $ParentForm,
        [parameter(Mandatory = $false)]
        [switch]$AppendVersion
    )
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, ($PSBoundParameters | Out-String)))
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

        # Icon and AppendVersion/Title are Window-only concepts - loading a non-Window root
        # (e.g. the per-tab UserControl fragment) must not attempt to set them.
        if ($Form -is [System.Windows.Window]) {
            $Form.Icon = Get-Icon -Type Wpf

            if ($AppendVersion) {
                "Set form title to: {0}" -f $Form.Title | Write-LogOutput -LogType DEBUG
                if ($Script:RunTimeConfig.ApplicationVersion -eq "Development") {
                    $Form.Title = "{0} (Development Version)" -f $Form.Title
                }
                else {
                    $Form.Title = "{0} v{1}" -f $Form.Title, $Script:RunTimeConfig.ApplicationVersion
                }
            }
        }

        $Elements = @()
        $ElementNames = @( "AccessText", "Button", "CheckBox", "ComboBox", "ComboBoxItem", "DataGrid", "Image", "Label", "PasswordBox", "RadioButton", "RichTextBox", "TabControl", "TextBlock", "TextBox", "TreeViewSqlSchema", "WebView2")
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
            if ([double]::IsNaN($Form.Height)) {
                $Form.Height = $ParentForm.Height
            }
            else {
                $Form.Height = [math]::Max($Form.Height, $ParentForm.Height)
            }
            if ($Form.Width -eq "NaN") {
                $Form.Width = $Form.MinWidth
            }
        }

        "Form Dimensions: {0}x{1}" -f $Form.Width, $Form.Height | Write-LogOutput -LogType DEBUG
        "Form Location: {0}x{1}" -f $Form.Left, $Form.Top | Write-LogOutput -LogType DEBUG

        "Return form object for: {0}" -f $Form.Name | Write-LogOutput -LogType DEBUG

        "Set Image Paths" | Write-LogOutput -LogType DEBUG
        foreach ($Element in ($Elements.Keys | ForEach-Object { $Elements.$_ | Where-Object { $_ -is [System.Windows.Controls.Image] -and $null -ne $_.Tag } })) {
            $ImagePath = Join-Path $Script:RunTimeConfig.ModuleFolder -ChildPath (Join-Path "lib\ui"  -ChildPath $Elements.($Element.Name).Tag)
            "Set path for image '{0}' to: {1}" -f $Element.Name, $ImagePath | Write-LogOutput -LogType DEBUG
            $Elements.($Element.Name).Source = $ImagePath
        }

        return [PSCustomObject]@{
            Definition      = $Form
            Elements        = $Elements
            Xaml            = $Xaml
            Position        = [PSCustomObject]@{
                Left = $null
                Top  = $null
            }
            Size            = [PSCustomObject]@{
                Width  = $Form.MinWidth
                Height = $Form.MinHeight
            }
            State           = "NotOpenend"
            PositionManager = @{
                Synchronizing       = $false
                PositionOffSetLeft  = 0
                PositionOffSetRight = 0
                PositionOffSetTop   = 0
                MainFormRight     = 0
                MainFormBottom    = 0
                ChildFormLeft     = 0
                ChildFormRight    = 0
                ChildFormBottom   = 0
                LastPositionChange  = Get-Date
            }
        }
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
