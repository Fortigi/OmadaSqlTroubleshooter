function Initialize-OmadaSqlTroubleShooter {
    [CmdLetBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'WebView2AlreadyLoaded', Justification = 'The variable is used, but script analyzer does not recognize it')]
    param()
    try {
        $Script:Tracer::WriteLine(("{0}: Function: {1} - Caller: {2}({3}) - Command: {4} - Parameters: {5}" -f $($Script:RunTimeConfig.ApplicationName), $($MyInvocation.MyCommand.Name), $($MyInvocation.ScriptName).Split("\")[-1], $($MyInvocation.ScriptLineNumber), $MyInvocation.Statement, (ConvertTo-RedactedLogString -InputObject $PSBoundParameters -MaxDepth 1)))
        "Initializing application..." | Write-LogOutput -LogType DEBUG
        Push-Location $Script:RunTimeConfig.ModuleFolder

        $Script:RunTimeConfig.Logging.AppLogObject.Add("Application log initialized`r`n")
        $Script:RunTimeConfig.ConfigFile.Name = $($Script:RunTimeConfig.ScriptName -replace ".ps1", ""), ".json" -join ""
        if (Test-Path $Script:RunTimeConfig.AppDataFolder -PathType Container) {
            New-Item (Join-Path $Script:RunTimeConfig.AppDataFolder -ChildPath "config") -ItemType Directory -Force | Out-Null
            $Script:RunTimeConfig.ConfigFile.Path = (Join-Path $($Script:RunTimeConfig.AppDataFolder) -ChildPath "config\$($Script:RunTimeConfig.ConfigFile.Name)")
        }
        else {
            $Script:RunTimeConfig.ConfigFile.Path = Join-Path $($Script:RunTimeConfig.ModuleFolder) -ChildPath $($Script:RunTimeConfig.ConfigFile.Name)
        }


        try {
            Get-Variable | Where-Object { $_.Name -eq "Task" } | Remove-Variable -Force -ErrorAction SilentlyContinue
        }
        catch { }

        "Load module OmadaWeb.PS" | Write-LogOutput -LogType DEBUG
        Import-Module OmadaWeb.PS
        "Load Assemblies" | Write-LogOutput -LogType DEBUG

        ("System.Windows.Forms", "System.Drawing", "PresentationFramework", "WindowsBase", "PresentationCore", "PresentationFramework") | ForEach-Object {
            "Load assembly: '{0}'" -f $_ | Write-LogOutput -LogType DEBUG
            try {
                Add-Type -AssemblyName $_
            }
            catch {
                if ($_.Exception.Message -like '*Assembly with same name is already loaded*') {}
                else { throw $_.Exception.Message }
            }
        }
        Add-ReflectionAssembly -Object $Script:WebView2CorePath
        Add-ReflectionAssembly -Object $Script:WebView2WinFormsPath
        Add-ReflectionAssembly -Object $Script:WebView2WpfPath

        # Custom panel that hosts the session tabs in a SINGLE row: instead of wrapping onto a new
        # row when they no longer fit (the default TabPanel behaviour), it shrinks the tabs
        # proportionally so their text ellipsises. The narrow "+" add tab (desired width <= 48) is
        # kept at its natural size; the real tabs shrink down to a 40px floor. Set as the
        # TabControl's ItemsPanel in MainForm.Definition.
        if (-not ([System.Management.Automation.PSTypeName]'Fortigi.ShrinkingTabPanel').Type) {
            $WpfReferencedAssemblies = [System.AppDomain]::CurrentDomain.GetAssemblies() |
                Where-Object { $_.GetName().Name -in @('PresentationCore', 'PresentationFramework', 'WindowsBase', 'System.Xaml') -and ![string]::IsNullOrEmpty($_.Location) } |
                ForEach-Object { $_.Location } | Select-Object -Unique
            Add-Type -ReferencedAssemblies $WpfReferencedAssemblies -TypeDefinition @"
using System;
using System.Windows;
using System.Windows.Controls;

namespace Fortigi {
    public class ShrinkingTabPanel : Panel {
        private double[] _widths;

        protected override Size MeasureOverride(Size availableSize) {
            int n = InternalChildren.Count;
            _widths = new double[n];
            double[] desired = new double[n];
            double fixedWidth = 0, flexDesired = 0;

            // Pass 1: each tab's natural (desired) width.
            for (int i = 0; i < n; i++) {
                UIElement child = InternalChildren[i];
                child.Measure(new Size(double.PositiveInfinity, availableSize.Height));
                desired[i] = child.DesiredSize.Width;
                if (desired[i] <= 48) { fixedWidth += desired[i]; } else { flexDesired += desired[i]; }
            }

            double available = double.IsInfinity(availableSize.Width) ? (fixedWidth + flexDesired) : availableSize.Width;
            double availableForFlex = Math.Max(0, available - fixedWidth);
            double scale = (flexDesired > availableForFlex && flexDesired > 0) ? (availableForFlex / flexDesired) : 1.0;

            // Pass 2: re-measure each tab at its allocated width so its content re-flows (and the
            // title text ellipsises) instead of just being clipped. Small tabs (the "+") stay fixed;
            // real tabs shrink down to a 40px floor.
            double total = 0, height = 0;
            for (int i = 0; i < n; i++) {
                double w = (desired[i] <= 48) ? desired[i] : Math.Max(40, desired[i] * scale);
                _widths[i] = w;
                UIElement child = InternalChildren[i];
                child.Measure(new Size(w, availableSize.Height));
                if (child.DesiredSize.Height > height) { height = child.DesiredSize.Height; }
                total += w;
            }

            double width = double.IsInfinity(availableSize.Width) ? total : availableSize.Width;
            return new Size(width, height);
        }

        protected override Size ArrangeOverride(Size finalSize) {
            double x = 0;
            for (int i = 0; i < InternalChildren.Count; i++) {
                double w = (_widths != null && i < _widths.Length) ? _widths[i] : InternalChildren[i].DesiredSize.Width;
                InternalChildren[i].Arrange(new Rect(x, 0, w, finalSize.Height));
                x += w;
            }
            return finalSize;
        }
    }
}
"@
        }

        # Stop WPF's TabControl from claiming Home/End (see Test-EditorNavigationKey for the full
        # story). TabControl.OnKeyDown is invoked through UIElement's class handler; a class handler
        # registered on the more derived TabControl runs FIRST, so marking the key handled here means
        # OnKeyDown never runs and the tab does not change. Marking it handled would normally also
        # withhold the key from Monaco - WebView2 only forwards a key to the web content when the WPF
        # routed event returns unhandled - so MainForm.Definition resets Handled at the end of the
        # bubble, once the TabControl can no longer act on it. Gated on the event coming from a
        # WebView2 so ordinary controls (TextBox, DataGrid) keep their normal Home/End behaviour.
        if (-not $Script:EditorNavigationKeyHandlerRegistered) {
            [System.Windows.EventManager]::RegisterClassHandler(
                [System.Windows.Controls.TabControl],
                [System.Windows.Input.Keyboard]::KeyDownEvent,
                [System.Windows.Input.KeyEventHandler] {
                    # $args[1] is the KeyEventArgs; the sender is not needed. Read from $args rather
                    # than a param block so the handler does not shadow PowerShell's automatic
                    # $EventArgs or declare a sender parameter it never uses.
                    $KeyEventArgs = $args[1]
                    if ((Test-EditorNavigationKey -KeyName ([string]$KeyEventArgs.Key)) -and $KeyEventArgs.OriginalSource -is [Microsoft.Web.WebView2.Wpf.WebView2]) {
                        $KeyEventArgs.Handled = $true
                    }
                })
            $Script:EditorNavigationKeyHandlerRegistered = $true
        }

        # Per-tab state ($RunTimeData/$WebView/$AppConfig/$ConnectionStatus/$Task/$MainForm.Elements)
        # now lives on each entry in $Script:Tabs and is repointed onto these same global names by
        # Set-ActiveTabContext, one tab at a time - see New-TabSession.ps1 for the per-tab shape
        # that used to be built here as a single, global instance.
        $Script:AppConfig = $null
        $Script:AppGlobalConfig = $null
        $Script:Tabs = [System.Collections.Generic.List[PSCustomObject]]::new()
        $Script:ActiveTabId = $null
        $Script:InteractiveLoginInProgress = $false
        $Script:SharedWebViewEnvironment = $null

        [Windows.Forms.Application]::EnableVisualStyles()

    }
    catch {
        throw $_
    }
}
