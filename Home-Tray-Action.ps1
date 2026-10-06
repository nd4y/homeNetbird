param([ValidateSet('up','down','status','routes')][string]$Mode='status')
$Host.UI.RawUI.WindowTitle = 'Home NetBird'
if ($Mode -in @('up','down')) {
    & (Join-Path $PSScriptRoot 'homenetbird.cmd') $Mode
} elseif ($Mode -eq 'status') {
    & (Join-Path $PSScriptRoot 'homenetbird.cmd') status -d
} else {
    & (Join-Path $PSScriptRoot 'homenetbird.cmd') routes list
}
Read-Host 'Press Enter to close'
