param([ValidateSet('up','down','status','routes')][string]$Mode='status',[switch]$SilentAction)
if($SilentAction){
    . (Join-Path $PSScriptRoot 'Home-Action-Worker.ps1')
    $result=Invoke-HomeSilentAction $Mode
    $result|ConvertTo-Json -Compress
    if($result.ok){exit 0}else{exit 1}
}
$Host.UI.RawUI.WindowTitle = 'Home NetBird'
if ($Mode -in @('up','down')) {
    throw 'Connect and Disconnect must be launched by the tray with -SilentAction.'
} elseif ($Mode -eq 'status') {
    & (Join-Path $PSScriptRoot 'homenetbird.cmd') status -d
} else {
    & (Join-Path $PSScriptRoot 'homenetbird.cmd') routes list
}
Read-Host 'Press Enter to close'
