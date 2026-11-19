# Size the result grids again whenever this tab's Results pane changes height. Loaded once per tab by
# Import-EventObjects, while $Script:MainForm.Elements points at the tab being built.
try {
    Register-QueryResultPaneResizeHandler -TabSession ([PSCustomObject]@{ Elements = $Script:MainForm.Elements })
}
catch {
    $_.Exception.Message | Write-ContainedErrorLog -ErrorObject $_
}
