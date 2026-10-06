param([string]$GoBinary='go',[switch]$SkipPrimaryInstaller)
$ErrorActionPreference = 'Stop'
$build = Join-Path $PSScriptRoot 'build'
$bin = Join-Path $PSScriptRoot 'bin'
New-Item -ItemType Directory -Path $build,$bin,(Join-Path $PSScriptRoot 'licenses') -Force | Out-Null
function Fetch-Verified([string]$Url,[string]$Path,[string]$Hash) {
    if (-not (Test-Path -LiteralPath $Path)) { Invoke-WebRequest -Uri $Url -OutFile $Path }
    if ((Get-FileHash -LiteralPath $Path).Hash -ne $Hash) { throw "Checksum mismatch for $Url" }
}
$zip = Join-Path $build 'netbird-v0.71.4.zip'
Fetch-Verified 'https://codeload.github.com/netbirdio/netbird/zip/refs/tags/v0.71.4' $zip 'CE4888E00BFDA91487FCF8092BFC4E44997162490493E3FC4F71F0B341AB1C40'
Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $build 'upstream') -Force
$source = Join-Path $build 'upstream\netbird-0.71.4'
& (Join-Path $PSScriptRoot 'Patch-NetBird.ps1') -SourceDirectory $source
$oldCGO=$env:CGO_ENABLED; $oldOS=$env:GOOS; $oldArch=$env:GOARCH
try {
    $env:CGO_ENABLED='0'; $env:GOOS='windows'; $env:GOARCH='amd64'
    Push-Location $source
    try {
        & $GoBinary fmt ./client/internal/dns ./client/firewall/uspfilter | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Go formatting failed' }
        & $GoBinary build -trimpath -buildvcs=false -ldflags '-s -w -X github.com/netbirdio/netbird/version.version=0.71.4-home-dual -X github.com/netbirdio/netbird/client/iface/device.CustomWindowsGUIDString={5c9483a8-3dc8-4f03-bdce-1d1257513582}' -o (Join-Path $bin 'netbird-home.exe') ./client
        if ($LASTEXITCODE -ne 0) { throw 'Daemon build failed' }
        $modules = @(& $GoBinary list -deps -f '{{if .Module}}{{.Module.Path}}|{{.Module.Version}}|{{.Module.Dir}}{{end}}' ./client | Where-Object {$_} | Sort-Object -Unique)
        if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate dependency licenses' }
        foreach ($module in $modules) {
            $parts=$module.Split('|'); $destination=Join-Path $PSScriptRoot ('licenses\dependencies\'+($parts[0] -replace '[^A-Za-z0-9._-]','_'))
            $notices=@(Get-ChildItem -LiteralPath $parts[2] -File | Where-Object {$_.Name -match '^(LICENSE|LICENCE|COPYING|NOTICE|COPYRIGHT)'} )
            if($notices.Count){New-Item -ItemType Directory -Path $destination -Force|Out-Null; $notices | Copy-Item -Destination $destination -Force}
        }
        $goRoot=& $GoBinary env GOROOT
        Copy-Item -LiteralPath (Join-Path $goRoot 'LICENSE') -Destination (Join-Path $PSScriptRoot 'licenses\GO-LICENSE.txt') -Force
    } finally { Pop-Location }
} finally { $env:CGO_ENABLED=$oldCGO; $env:GOOS=$oldOS; $env:GOARCH=$oldArch }
$wintunZip=Join-Path $build 'wintun-0.14.1.zip'
Fetch-Verified 'https://www.wintun.net/builds/wintun-0.14.1.zip' $wintunZip '07C256185D6EE3652E09FA55C0B673E2624B565E02C4B9091C79CA7D2F24EF51'
Expand-Archive -LiteralPath $wintunZip -DestinationPath (Join-Path $build 'wintun') -Force
Copy-Item -LiteralPath (Join-Path $build 'wintun\wintun\bin\amd64\wintun.dll') -Destination $bin -Force
Copy-Item -LiteralPath (Join-Path $build 'wintun\wintun\LICENSE.txt') -Destination (Join-Path $PSScriptRoot 'licenses\WINTUN-LICENSE.txt') -Force
if (-not $SkipPrimaryInstaller) {
    Fetch-Verified 'https://github.com/netbirdio/netbird/releases/download/v0.71.4/netbird_installer_0.71.4_windows_amd64.msi' (Join-Path $bin 'netbird-primary.msi') '85DC1471AF237F58ABDC556D29E4A95DBC889DBFBAAF2B52DB1FF5EA48FFF406'
}
$files=@(Get-ChildItem -LiteralPath $bin -File | ForEach-Object {[ordered]@{name=$_.Name;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant();bytes=$_.Length}})
$manifest=[ordered]@{version='1.1.0';upstream='0.71.4';architecture='windows-amd64';files=$files}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'release-manifest.json'),($manifest|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Host 'Bundled daemon, Wintun, upstream installer and release manifest ready.'
