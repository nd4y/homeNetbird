param([string]$ManagementUrl='https://api.netbird.io:443')
$Host.UI.RawUI.WindowTitle='homeNetbird - Home sign-in'
& (Join-Path $PSScriptRoot 'homenetbird.cmd') up --profile default --management-url $ManagementUrl --interface-name wt1 --wireguard-port 51821 --disable-server-routes --disable-client-routes --disable-ipv6 --disable-auto-connect=false
if($LASTEXITCODE -eq 0){
    & (Join-Path $PSScriptRoot 'homenetbird.cmd') routes deselect all
    if($LASTEXITCODE -eq 0){Start-Process powershell.exe -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Home-Routes.ps1')+'"')) -WindowStyle Hidden}
    Write-Host 'Home is connected. Choose only needed router networks in the route picker; the tray menu can reopen it.'
}
else{Write-Host 'Home sign-in did not complete. The service is installed; retry with homenetbird up.'}
Read-Host 'Press Enter to close'
