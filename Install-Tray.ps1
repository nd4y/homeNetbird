param(
    [string]$Destination=(Join-Path $env:LOCALAPPDATA 'Programs\NetBirdHomeTray'),
    [switch]$NoStartup,
    [switch]$NoDesktop,
    [switch]$NoPath,
    [switch]$NoLaunch
)
$ErrorActionPreference = 'Stop'
$Destination = [IO.Path]::GetFullPath($Destination)
$source = [IO.Path]::GetFullPath($PSScriptRoot)
if ($source.TrimEnd('\') -ne $Destination.TrimEnd('\')) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($file in @('Home-Tray.ps1','Home-Tray-Action.ps1','Home-Settings.ps1','Check-HomeIdentity.ps1','Connect-Home.ps1','Home-Routes.ps1','Update-HomeDNS.ps1','Remove-Service.ps1','homenetbird.cmd','Install-Tray.ps1','Uninstall.ps1','README.md','LICENSE','NETBIRD-LICENSE','NOTICE')) {
        Copy-Item -LiteralPath (Join-Path $source $file) -Destination $Destination -Force
    }
    Copy-Item -LiteralPath (Join-Path $source 'icons') -Destination $Destination -Recurse -Force
    if(Test-Path (Join-Path $source 'licenses')){Copy-Item -LiteralPath (Join-Path $source 'licenses') -Destination $Destination -Recurse -Force}
}
$trayScript = Join-Path $Destination 'Home-Tray.ps1'
$shell = New-Object -ComObject WScript.Shell
$target = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$trayScript+'"'
$links = @()
if (-not $NoStartup) { $links += Join-Path ([Environment]::GetFolderPath('Startup')) 'Home NetBird Tray.lnk' }
if (-not $NoDesktop) { $links += Join-Path ([Environment]::GetFolderPath('Desktop')) 'Home NetBird Tray.lnk' }
foreach ($link in $links) {
    $shortcut = $shell.CreateShortcut($link)
    $shortcut.TargetPath = $target; $shortcut.Arguments = $arguments
    $shortcut.WorkingDirectory = $Destination; $shortcut.WindowStyle = 7
    $shortcut.IconLocation = (Join-Path $Destination 'icons\home-connected.ico')+',0'
    $shortcut.Save()
}
if (-not $NoPath) {
    $userPath = [Environment]::GetEnvironmentVariable('Path','User')
    $entries = @($userPath -split ';' | Where-Object {$_})
    if ($Destination -notin $entries) { [Environment]::SetEnvironmentVariable('Path', (($entries + $Destination) -join ';'), 'User') }
}
if (-not $NoLaunch) { Start-Process $target -ArgumentList $arguments -WindowStyle Hidden }
Write-Host "Installed in $Destination. Open a fresh terminal for homenetbird."
