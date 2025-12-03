function Invoke-GenerateDiffView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$OldValue,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$NewValue
    )

    try {
        "Generating diff view..." | Write-LogOutput -LogType DEBUG

        $Script:SqlHistoryForm.Elements.RichTextBoxOldDiff.Document.Blocks.Clear()
        $Script:SqlHistoryForm.Elements.RichTextBoxNewDiff.Document.Blocks.Clear()

        $OldLines = if ([string]::IsNullOrWhiteSpace($OldValue)) { @() } else { $OldValue -split "`r?`n" }
        $NewLines = if ([string]::IsNullOrWhiteSpace($NewValue)) { @() } else { $NewValue -split "`r?`n" }

        $MaxLines = [Math]::Max($OldLines.Count, $NewLines.Count)

        $OldDocument = New-Object System.Windows.Documents.FlowDocument
        $NewDocument = New-Object System.Windows.Documents.FlowDocument

        for ($i = 0; $i -lt $MaxLines; $i++) {
            $OldLine = if ($i -lt $OldLines.Count) { $OldLines[$i] } else { "" }
            $NewLine = if ($i -lt $NewLines.Count) { $NewLines[$i] } else { "" }

            $OldParagraph = New-Object System.Windows.Documents.Paragraph
            $NewParagraph = New-Object System.Windows.Documents.Paragraph

            $OldParagraph.Margin = New-Object System.Windows.Thickness(0, 0, 0, 2)
            $NewParagraph.Margin = New-Object System.Windows.Thickness(0, 0, 0, 2)

            $OldRun = New-Object System.Windows.Documents.Run
            $NewRun = New-Object System.Windows.Documents.Run

            $OldRun.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
            $NewRun.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
            $OldRun.FontSize = 14
            $NewRun.FontSize = 14

            if ($OldLine -ne $NewLine) {
                if ($i -ge $OldLines.Count) {
                    $NewRun.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(170, 255, 170))
                    $NewParagraph.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(170, 255, 170))
                    $OldRun.Text = ""
                    $NewRun.Text = $NewLine
                }
                elseif ($i -ge $NewLines.Count) {
                    $OldRun.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(255, 170, 170))
                    $OldParagraph.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(255, 170, 170))
                    $OldRun.Text = $OldLine
                    $NewRun.Text = ""
                }
                else {
                    $OldRun.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(255, 170, 170))
                    $NewRun.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(170, 255, 170))
                    $OldParagraph.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(255, 170, 170))
                    $NewParagraph.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(170, 255, 170))
                    $OldRun.Text = $OldLine
                    $NewRun.Text = $NewLine
                }
            }
            else {
                $OldRun.Text = $OldLine
                $NewRun.Text = $NewLine
            }

            $OldParagraph.Inlines.Add($OldRun)
            $NewParagraph.Inlines.Add($NewRun)

            $OldDocument.Blocks.Add($OldParagraph)
            $NewDocument.Blocks.Add($NewParagraph)
        }

        $Script:SqlHistoryForm.Elements.RichTextBoxOldDiff.Document = $OldDocument
        $Script:SqlHistoryForm.Elements.RichTextBoxNewDiff.Document = $NewDocument

        "Diff view generated successfully" | Write-LogOutput -LogType DEBUG
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
