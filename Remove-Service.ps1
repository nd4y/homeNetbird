$ErrorActionPreference='Stop'
$state=Join-Path $env:ProgramData 'homeNetbird'
$machine=Join-Path $env:ProgramFiles 'homeNetbird'
$marker=Join-Path $state 'installed-by-homeNetbird.json'
if(-not (Test-Path -LiteralPath $marker)){throw 'No owned homeNetbird installation found. Existing unrelated services are not removed.'}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run this removal script as administrator.'}
$service=Get-Service NetbirdHome -ErrorAction SilentlyContinue
if($service){
    $image=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\NetbirdHome').ImagePath
    if(-not $image.StartsWith('"'+(Join-Path $machine 'netbird-home.exe')+'" ',[StringComparison]::OrdinalIgnoreCase)){throw 'Service belongs to another installation.'}
    Stop-Service NetbirdHome
    & sc.exe delete NetbirdHome | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Could not remove Home service'}
}
Write-Host 'Home service removed. Primary NetBird unchanged. Protected Home keys and binaries are retained for recovery; remove them manually only after deciding whether to keep a backup.'
