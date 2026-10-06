param([string]$Domains='', [Parameter(Mandatory)][string]$ResultPath)
$ErrorActionPreference='Stop'
try{
    $state=Join-Path $env:ProgramData 'homeNetbird'
    $machine=Join-Path $env:ProgramFiles 'homeNetbird'
    $marker=Get-Content (Join-Path $state 'installed-by-homeNetbird.json') -Raw|ConvertFrom-Json
    if($marker.product -ne 'homeNetbird'){throw 'No owned homeNetbird installation'}
    $image=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\NetbirdHome').ImagePath
    if(-not $image.StartsWith('"'+(Join-Path $machine 'netbird-home.exe')+'" ',[StringComparison]::OrdinalIgnoreCase)){throw 'Service belongs to another installation'}
    $all=@(($marker.extraDomains+','+$Domains).Split(',')|ForEach-Object {$_.Trim()}|Where-Object {$_}|Sort-Object -Unique)
    foreach($domain in $all){if($domain -notmatch '^(?:\*\.)?(?:[a-zA-Z0-9_][a-zA-Z0-9_-]*\.)+[a-zA-Z0-9_][a-zA-Z0-9_-]*$'){throw 'Invalid DNS namespace'}}
    $key='HKLM:\SYSTEM\CurrentControlSet\Services\NetbirdHome'
    $existing=@((Get-ItemProperty $key).Environment)
    $next='NB_DUAL_EXTRA_DOMAINS='+($all -join ',')
    if($next -notin $existing){
        $new=@($existing|Where-Object {$_ -notlike 'NB_DUAL_EXTRA_DOMAINS=*'})+@($next)
        New-ItemProperty -Path $key -Name Environment -PropertyType MultiString -Value $new -Force|Out-Null
        Restart-Service NetbirdHome
    }
    $result=@{ok=$true}
}catch{$result=@{ok=$false;error=$_.Exception.Message}}
[IO.File]::WriteAllText($ResultPath,($result|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
if(-not $result.ok){exit 1}
