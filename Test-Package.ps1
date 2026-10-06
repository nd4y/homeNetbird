# Read-only package validation plus an unregistered, disconnected daemon on a test endpoint.
$ErrorActionPreference='Stop'
$manifest=Get-Content (Join-Path $PSScriptRoot 'release-manifest.json') -Raw|ConvertFrom-Json
foreach($file in $manifest.files){if((Get-FileHash (Join-Path $PSScriptRoot ('bin\'+$file.name))).Hash -ne $file.sha256){throw 'Package hash mismatch'}}
foreach($file in Get-ChildItem $PSScriptRoot -Filter '*.ps1'){
    $tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)|Out-Null
    if($errors){throw ($errors|Out-String)}
}
Add-Type -AssemblyName System.Drawing
foreach($file in Get-ChildItem (Join-Path $PSScriptRoot 'icons') -Filter '*.ico'){
    foreach($size in @(16,20,24,32,48,64)){$icon=[Drawing.Icon]::new($file.FullName,$size,$size);if($icon.Width -ne $size){throw 'Incorrect icon frame size'};$icon.Dispose()}
}
if(Get-NetTCPConnection -LocalPort 41991 -State Listen -ErrorAction SilentlyContinue){throw 'Test endpoint 41991 is in use'}
$testDir=Join-Path $env:TEMP ('homeNetbird-daemon-test-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $testDir|Out-Null
$account=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $testDir /inheritance:r /grant:r ('*'+$account+':(OI)(CI)F') '*S-1-5-18:(OI)(CI)F'|Out-Null
if($LASTEXITCODE -ne 0){throw 'Could not protect test state'}
$config=Join-Path $testDir 'default.json'
$seed=@{WgIface='homeTest';WgPort=51991;DisableAutoConnect=$true;DisableClientRoutes=$true;DisableServerRoutes=$true;DisableIPv6=$true;ServerSSHAllowed=$false}
[IO.File]::WriteAllText($config,($seed|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$oldState=$env:NB_STATE_DIR;$oldDomains=$env:NB_DUAL_EXTRA_DOMAINS;$process=$null
try{
    $env:NB_STATE_DIR=$testDir;$env:NB_DUAL_EXTRA_DOMAINS='home.example.test'
    $binary=Join-Path $PSScriptRoot 'bin\netbird-home.exe'
    $process=Start-Process $binary -ArgumentList @('service','run','--service','HomeNetbirdTest','--daemon-addr','tcp://127.0.0.1:41991','--config',('"'+$config+'"'),'--log-file',('"'+(Join-Path $testDir 'client.log')+'"')) -WindowStyle Hidden -PassThru
    $env:NB_STATE_DIR=$oldState;$env:NB_DUAL_EXTRA_DOMAINS=$oldDomains
    $deadline=(Get-Date).AddSeconds(15);$fresh=$null
    do{
        $ErrorActionPreference='SilentlyContinue'
        $raw=& $binary --daemon-addr tcp://127.0.0.1:41991 status --json 2>$null
        $probeExit=$LASTEXITCODE;$ErrorActionPreference='Stop'
        if($probeExit -eq 0){$fresh=$raw|ConvertFrom-Json;break}
        Start-Sleep -Milliseconds 300
    }while((Get-Date) -lt $deadline)
    if(-not $fresh){throw 'Fresh daemon did not respond'}
    $generated=Get-Content $config -Raw|ConvertFrom-Json
    if(-not $generated.PrivateKey -or $generated.WgIface -ne 'homeTest' -or -not $generated.DisableAutoConnect -or -not $generated.DisableClientRoutes){throw 'Fresh daemon config initialization failed'}
    [pscustomobject]@{PackageHashes=$true;PowerShellSyntax=$true;IconFrames=$true;FreshDaemonStatus=$fresh.daemonStatus;Version=$fresh.daemonVersion;NewIdentityGenerated=$true;StateIsolated=$true;PrivateTestState=$testDir}|ConvertTo-Json
}finally{
    $env:NB_STATE_DIR=$oldState;$env:NB_DUAL_EXTRA_DOMAINS=$oldDomains
    if($process -and -not $process.HasExited){$process.Kill();$process.WaitForExit();$process.Dispose()}
    # Retain protected test state for review; never print its contents or touch production state.
}
