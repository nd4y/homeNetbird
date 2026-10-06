$ErrorActionPreference='Stop'
$dist=Join-Path $PSScriptRoot 'dist'
$stage=Join-Path $dist ('stage-'+[guid]::NewGuid())
$package=Join-Path $stage 'homeNetbird'
New-Item -ItemType Directory -Path $package -Force|Out-Null
$files=@('Setup.cmd','Setup.ps1','Install.ps1','Install-Service.ps1','Install-Tray.ps1','Connect-Home.ps1','Home-Routes.ps1','Update-HomeDNS.ps1','Remove-Service.ps1','Home-Tray.ps1','Home-Tray-Action.ps1','Home-Settings.ps1','Check-HomeIdentity.ps1','homenetbird.cmd','Uninstall.ps1','README.md','LICENSE','NETBIRD-LICENSE','NOTICE','release-manifest.json','Build.ps1','Patch-NetBird.ps1','Test-Package.ps1','Package.ps1','Build-Setup.ps1','SetupLauncher.cs','SetupLauncher.manifest')
foreach($file in $files){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $package}
foreach($folder in @('icons','licenses','bin')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $folder) -Destination $package -Recurse}
$zip=Join-Path $dist 'homeNetbird-1.1.0-windows-amd64.zip'
Compress-Archive -LiteralPath $package -DestinationPath $zip -Force
Compress-Archive -LiteralPath (Join-Path $PSScriptRoot 'build\upstream\netbird-0.71.4') -DestinationPath (Join-Path $dist 'homeNetbird-netbird-source-0.71.4.zip') -Force
Write-Host "Release ZIP: $zip"
