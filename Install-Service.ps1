param(
    [string]$ExtraDomains='',
    [Parameter(Mandatory)][string]$ResultPath,
    [switch]$ValidateOnly
)
$ErrorActionPreference='Stop'
$machine=Join-Path $env:ProgramFiles 'homeNetbird'
$state=Join-Path $env:ProgramData 'homeNetbird'
$serviceName='NetbirdHome'
$createdService=$false
function Write-Result($value) {[IO.File]::WriteAllText($ResultPath,($value|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))}
try {
    $manifest=Get-Content (Join-Path $PSScriptRoot 'release-manifest.json') -Raw | ConvertFrom-Json
    foreach($file in $manifest.files){
        if($file.name -notin @('netbird-home.exe','wintun.dll','netbird-primary.msi')){throw 'Invalid package manifest'}
        $path=Join-Path $PSScriptRoot ('bin\'+$file.name)
        if((Get-FileHash -LiteralPath $path).Hash -ne $file.sha256){throw ('Package checksum mismatch: '+$file.name)}
    }
    foreach($required in @('netbird-home.exe','wintun.dll')){if($required -notin @($manifest.files.name)){throw ('Package missing '+$required)}}
    foreach($domain in @($ExtraDomains.Split(',')|ForEach-Object {$_.Trim()}|Where-Object {$_})) {
        if($domain -notmatch '^(?:\*\.)?(?:[a-zA-Z0-9_][a-zA-Z0-9_-]*\.)+[a-zA-Z0-9_][a-zA-Z0-9_-]*$'){throw 'Enter fully qualified DNS domains; root and catch-all namespaces are not allowed.'}
    }
    $existing=Get-Service $serviceName -ErrorAction SilentlyContinue
    if($existing){throw 'NetbirdHome already exists. Existing Home installations are never overwritten; remove or migrate them explicitly first.'}
    if((Test-Path -LiteralPath $state) -or (Test-Path -LiteralPath $machine)){throw 'Existing homeNetbird directories found; refusing to overwrite saved state.'}
    if(Get-NetTCPConnection -LocalPort 41732 -State Listen -ErrorAction SilentlyContinue){throw 'TCP port 41732 is already in use.'}
    if(Get-NetUDPEndpoint -LocalPort 51821 -ErrorAction SilentlyContinue){throw 'UDP port 51821 is already in use.'}
    if(Get-NetAdapter -Name wt1 -ErrorAction SilentlyContinue){throw 'Interface wt1 already exists.'}
    if($ValidateOnly){Write-Result @{ok=$true;validated=$true;service=$serviceName};exit 0}
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if(-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator rights are required to install the VPN service.'}
    $primary=Join-Path $env:ProgramFiles 'Netbird\netbird.exe'
    if(-not (Test-Path -LiteralPath $primary)){
        $msi=Join-Path $PSScriptRoot 'bin\netbird-primary.msi'
        if(-not (Test-Path -LiteralPath $msi)){throw 'Install primary NetBird first, or use the full release ZIP containing its installer.'}
        $installer=Start-Process msiexec.exe -ArgumentList @('/i',('"'+$msi+'"'),'/qn','/norestart') -WindowStyle Hidden -Wait -PassThru
        if($installer.ExitCode -notin @(0,3010)){throw ('Primary NetBird installation failed: '+$installer.ExitCode)}
    }
    New-Item -ItemType Directory -Path $machine,$state -Force|Out-Null
    & icacls.exe $machine /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Could not protect executable directory'}
    & icacls.exe $state /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Could not protect private state directory'}
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin\netbird-home.exe'),(Join-Path $PSScriptRoot 'bin\wintun.dll') -Destination $machine
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'licenses') -Destination $machine -Recurse
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'NETBIRD-LICENSE'),(Join-Path $PSScriptRoot 'NOTICE') -Destination $machine
    [IO.File]::WriteAllText((Join-Path $state 'installed-by-homeNetbird.json'),(@{product='homeNetbird';schema=1;extraDomains=$ExtraDomains}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    # No identity is imported: the daemon generates fresh keys in protected storage.
    $seed=@{WgIface='wt1';WgPort=51821;DisableAutoConnect=$true;DisableClientRoutes=$true;DisableServerRoutes=$true;DisableDNS=$false;DisableFirewall=$false;DisableIPv6=$true;ServerSSHAllowed=$false}
    [IO.File]::WriteAllText((Join-Path $state 'default.json'),($seed|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    $image='"'+(Join-Path $machine 'netbird-home.exe')+'" service run --service NetbirdHome --daemon-addr tcp://127.0.0.1:41732 --config "'+(Join-Path $state 'default.json')+'" --log-file "'+(Join-Path $state 'client.log')+'"'
    New-Service -Name $serviceName -DisplayName 'NetBird Home' -StartupType Automatic -BinaryPathName $image|Out-Null
    $createdService=$true
    $key='HKLM:\SYSTEM\CurrentControlSet\Services\'+$serviceName
    New-ItemProperty -Path $key -Name Environment -PropertyType MultiString -Value @("NB_STATE_DIR=$state","NB_DUAL_EXTRA_DOMAINS=$ExtraDomains") -Force|Out-Null
    New-ItemProperty -Path $key -Name DelayedAutoStart -PropertyType DWord -Value 1 -Force|Out-Null
    Start-Service $serviceName
    $deadline=(Get-Date).AddSeconds(20)
    do {
        $ErrorActionPreference='SilentlyContinue'
        $probe=& (Join-Path $machine 'netbird-home.exe') --daemon-addr tcp://127.0.0.1:41732 status --json 2>$null
        $probeExit=$LASTEXITCODE;$ErrorActionPreference='Stop'
        if($probeExit -eq 0){$null=$probe|ConvertFrom-Json;break}
        Start-Sleep -Milliseconds 500
    }while((Get-Date) -lt $deadline)
    if($probeExit -ne 0){throw 'Home daemon did not become ready'}
    Write-Result @{ok=$true;service=$serviceName;binary=(Join-Path $machine 'netbird-home.exe')}
    exit 0
}catch{
    if($createdService){Stop-Service $serviceName -ErrorAction SilentlyContinue; & sc.exe delete $serviceName|Out-Null}
    # Preserve any newly generated state for diagnosis; never delete keys automatically.
    Write-Result @{ok=$false;error=$_.Exception.Message}
    exit 1
}
