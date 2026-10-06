$ErrorActionPreference='Stop'
$dist=Join-Path $PSScriptRoot 'dist'
$zip=Join-Path $dist 'homeNetbird-1.1.0-windows-amd64.zip'
$zipHash=(Get-FileHash $zip).Hash.ToLowerInvariant()
$source=Join-Path $dist 'SetupLauncher.generated.cs'
$text=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'SetupLauncher.cs')).Replace('__PAYLOAD_SHA256__',$zipHash)
[IO.File]::WriteAllText($source,$text,[Text.UTF8Encoding]::new($false))
$output=Join-Path $dist 'homeNetbird-Setup.exe'
$framework=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319'
$compiler=Join-Path $framework 'csc.exe'
$arguments=@('/nologo','/target:winexe','/platform:x64','/optimize+',('/out:'+$output),('/win32icon:'+(Join-Path $PSScriptRoot 'icons\home-connected.ico')),('/win32manifest:'+(Join-Path $PSScriptRoot 'SetupLauncher.manifest')),('/resource:'+$zip+',homeNetbird.payload.zip'),'/reference:System.Windows.Forms.dll',('/reference:'+(Join-Path $framework 'System.IO.Compression.dll')),('/reference:'+(Join-Path $framework 'System.IO.Compression.FileSystem.dll')),$source)
& $compiler @arguments
if($LASTEXITCODE -ne 0 -or -not (Test-Path $output)){throw 'Setup launcher compilation failed'}
$checksums=@($zip,(Join-Path $dist 'homeNetbird-netbird-source-0.71.4.zip'),$output)|ForEach-Object {((Get-FileHash $_).Hash.ToLowerInvariant())+'  '+(Split-Path $_ -Leaf)}
[IO.File]::WriteAllLines((Join-Path $dist 'SHA256SUMS.txt'),[string[]]$checksums,[Text.UTF8Encoding]::new($false))
Write-Host "Single-file installer: $output"