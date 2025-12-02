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

        # Clear existing content
        $Script:SqlHistoryWindowForm.Elements.RichTextBoxOldDiff.Document.Blocks.Clear()
        $Script:SqlHistoryWindowForm.Elements.RichTextBoxNewDiff.Document.Blocks.Clear()

        # Handle null or empty values
        $OldLines = if ([string]::IsNullOrWhiteSpace($OldValue)) { @() } else { $OldValue -split "`r?`n" }
        $NewLines = if ([string]::IsNullOrWhiteSpace($NewValue)) { @() } else { $NewValue -split "`r?`n" }

        # Simple line-by-line diff algorithm
        $MaxLines = [Math]::Max($OldLines.Count, $NewLines.Count)

        # Create FlowDocuments for both sides
        $OldDocument = New-Object System.Windows.Documents.FlowDocument
        $NewDocument = New-Object System.Windows.Documents.FlowDocument

        for ($i = 0; $i -lt $MaxLines; $i++) {
            $OldLine = if ($i -lt $OldLines.Count) { $OldLines[$i] } else { "" }
            $NewLine = if ($i -lt $NewLines.Count) { $NewLines[$i] } else { "" }

            # Create paragraphs for each line
            $OldParagraph = New-Object System.Windows.Documents.Paragraph
            $NewParagraph = New-Object System.Windows.Documents.Paragraph

            # Set line height and margin
            $OldParagraph.Margin = New-Object System.Windows.Thickness(0, 0, 0, 2)
            $NewParagraph.Margin = New-Object System.Windows.Thickness(0, 0, 0, 2)

            # Create runs for the text content
            $OldRun = New-Object System.Windows.Documents.Run
            $NewRun = New-Object System.Windows.Documents.Run

            # Set font family for better readability
            $OldRun.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
            $NewRun.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
            $OldRun.FontSize = 11
            $NewRun.FontSize = 11

            # Compare lines and set styling
            if ($OldLine -ne $NewLine) {
                if ($i -ge $OldLines.Count) {
                    # Line only exists in new version (added)
                    $NewRun.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(230, 255, 230))
                    $NewParagraph.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(230, 255, 230))
                    $OldRun.Text = ""
                    $NewRun.Text = $NewLine
                }
                elseif ($i -ge $NewLines.Count) {
                    # Line only exists in old version (removed)
                    $OldRun.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(255, 230, 230))
                    $OldParagraph.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(255, 230, 230))
                    $OldRun.Text = $OldLine
                    $NewRun.Text = ""
                }
                else {
                    # Lines are different (modified)
                    $OldRun.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(255, 230, 230))
                    $NewRun.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(230, 255, 230))
                    $OldParagraph.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(255, 230, 230))
                    $NewParagraph.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromRgb(230, 255, 230))
                    $OldRun.Text = $OldLine
                    $NewRun.Text = $NewLine
                }
            }
            else {
                # Lines are identical
                $OldRun.Text = $OldLine
                $NewRun.Text = $NewLine
            }

            # Add runs to paragraphs
            $OldParagraph.Inlines.Add($OldRun)
            $NewParagraph.Inlines.Add($NewRun)

            # Add paragraphs to documents
            $OldDocument.Blocks.Add($OldParagraph)
            $NewDocument.Blocks.Add($NewParagraph)
        }

        # Set documents to RichTextBoxes
        $Script:SqlHistoryWindowForm.Elements.RichTextBoxOldDiff.Document = $OldDocument
        $Script:SqlHistoryWindowForm.Elements.RichTextBoxNewDiff.Document = $NewDocument

        "Diff view generated successfully" | Write-LogOutput -LogType DEBUG
    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR -ErrorObject $_
    }
}
