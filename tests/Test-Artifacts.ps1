$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$manifest=Get-Content (Join-Path $root 'release-manifest.json') -Raw|ConvertFrom-Json
$dist=Join-Path $root 'dist'
$zip=Join-Path $dist ('homeNetbird-'+$manifest.version+'-windows-amd64.zip')
$exe=Join-Path $dist 'homeNetbird-Setup.exe'
foreach($line in Get-Content (Join-Path $dist 'SHA256SUMS.txt')){
    if($line -notmatch '^([a-fA-F0-9]{64})  ([A-Za-z0-9._-]+)$'){throw 'Invalid checksum entry'}
    $expected=$Matches[1];$name=$Matches[2]
    if((Get-FileHash -LiteralPath (Join-Path $dist $name)).Hash -ne $expected){throw ('Release checksum mismatch: '+$name)}
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($zip)
try {
    $entries=@($archive.Entries|ForEach-Object {$_.FullName.Replace([char]92,[char]47)})
    foreach($file in @('Setup.cmd','Setup.ps1','bin/netbird-home.exe','bin/wintun.dll','bin/netbird-primary.msi','Home-Tray-Actions.ps1','Home-Action-Worker.ps1','icons/home-connecting.ico','icons/home-preview.png','licenses/WINTUN-LICENSE.txt')){
        if(('homeNetbird/'+$file) -notin $entries){throw ('Missing runtime asset: '+$file)}
    }
    $privateNames=@('default.json','client.log','tray-status.json','state.json')
    foreach($entry in $entries){$name=($entry -split '/')[-1];if($name -in $privateNames -or $name -like 'active_profile*'){throw 'Private runtime state found in package'}}
    if((Get-FileHash (Join-Path $root 'icons/home-preview.png')).Hash -ne 'D4FDF9322980C7E51D1BC640E21E74120BA17BC245F144AA6FF8DAACB90E8621'){throw 'Original Aurora preview changed'}
}finally{$archive.Dispose()}
$assembly=[Reflection.Assembly]::LoadFile($exe)
$stream=$assembly.GetManifestResourceStream('homeNetbird.payload.zip')
if($null -eq $stream){throw 'Installer payload is missing'}
$hash=[Security.Cryptography.SHA256]::Create()
try {
    $embedded=([BitConverter]::ToString($hash.ComputeHash($stream))).Replace('-','')
    if($embedded -ne (Get-FileHash $zip).Hash){throw 'Embedded installer ZIP differs from release ZIP'}
}finally{$hash.Dispose();$stream.Dispose()}
'PASS: release checksums, required runtime files, no private runtime state, original artwork, embedded installer payload.'
