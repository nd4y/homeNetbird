param([switch]$ListOnly)
. (Join-Path $PSScriptRoot 'Home-Settings.ps1')
$settings=Get-HomeSettings
$originalAppData=$env:APPDATA
$env:APPDATA=$settings.CacheDirectory
function Test-CidrOverlap([string]$A,[string]$B) {
    if($A -notmatch '^([0-9.]+)/([0-9]+)$'){return $false}
    $aPrefix=[int]$Matches[2];$aBytes=[Net.IPAddress]::Parse($Matches[1]).GetAddressBytes()
    if($B -notmatch '^([0-9.]+)/([0-9]+)$'){return $false}
    $bPrefix=[int]$Matches[2];$bBytes=[Net.IPAddress]::Parse($Matches[1]).GetAddressBytes()
    $prefix=[Math]::Min($aPrefix,$bPrefix)
    for($i=0;$i -lt 4;$i++){
        $bits=[Math]::Min(8,[Math]::Max(0,$prefix-8*$i))
        $mask=if($bits -eq 0){0}else{256-[Math]::Pow(2,8-$bits)}
        if(($aBytes[$i] -band [int]$mask) -ne ($bBytes[$i] -band [int]$mask)){return $false}
    }
    return $true
}
try {
    $output=& $settings.BinaryPath --daemon-addr $settings.DaemonAddress routes list
    if($LASTEXITCODE -ne 0){throw 'Could not read Home routes'}
    $networks=@();$current=$null
    foreach($line in $output){
        if($line -match '^\s*- ID: (.+)$'){$current=[pscustomobject]@{Id=$Matches[1];Target='';Kind='';Selected=$false;Overlap=''};$networks+=$current}
        elseif($null -ne $current -and $line -match '^\s*(Network|Domains): (.+)$'){$current.Kind=$Matches[1];$current.Target=$Matches[2]}
        elseif($null -ne $current -and $line -match '^\s*Status: Selected$'){$current.Selected=$true}
    }
    $existing=@(Get-NetRoute -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -ne 'wt1' -and $_.DestinationPrefix -notin @('0.0.0.0/0','224.0.0.0/4','255.255.255.255/32')})
    foreach($network in $networks){
        if($network.Kind -eq 'Network'){
            $conflicts=@($existing|Where-Object {Test-CidrOverlap $network.Target $_.DestinationPrefix})
            $network.Overlap=(@($conflicts.InterfaceAlias|Sort-Object -Unique)-join ', ')
        }
    }
    if($ListOnly){$networks;return}
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form=New-Object Windows.Forms.Form;$form.Text='homeNetbird - choose Home routes';$form.Size=New-Object Drawing.Size(760,460);$form.StartPosition='CenterScreen'
    $list=New-Object Windows.Forms.ListView;$list.Location=New-Object Drawing.Point(15,15);$list.Size=New-Object Drawing.Size(715,325);$list.View='Details';$list.CheckBoxes=$true;$list.FullRowSelect=$true
    $list.Columns.Add('Home network',210)|Out-Null;$list.Columns.Add('Destination',320)|Out-Null;$list.Columns.Add('Overlaps with',175)|Out-Null
    foreach($network in $networks){$item=[Windows.Forms.ListViewItem]::new($network.Id);$item.SubItems.Add($network.Target)|Out-Null;$item.SubItems.Add($network.Overlap)|Out-Null;$item.Checked=$network.Selected;$item.Tag=$network;$list.Items.Add($item)|Out-Null}
    $form.Controls.Add($list)
    $note=New-Object Windows.Forms.Label;$note.Text='Choose only needed networks. Overlaps can redirect traffic from your LAN or primary VPN.';$note.Location=New-Object Drawing.Point(15,350);$note.Size=New-Object Drawing.Size(715,25);$form.Controls.Add($note)
    $apply=New-Object Windows.Forms.Button;$apply.Text='Apply selected routes';$apply.Location=New-Object Drawing.Point(15,380);$apply.Size=New-Object Drawing.Size(220,30);$form.Controls.Add($apply)
    $apply.Add_Click({
        $apply.Enabled=$false
        try {
            $chosen=@($list.CheckedItems|ForEach-Object {$_.Tag})
            if(@($chosen|Where-Object {$_.Overlap}).Count){
                $answer=[Windows.Forms.MessageBox]::Show('Some selected networks overlap existing routes. More specific routes can take precedence. Apply this selection?','Route overlap',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning)
                if($answer -ne [Windows.Forms.DialogResult]::Yes){return}
            }
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Check-HomeIdentity.ps1')
            if($LASTEXITCODE -ne 0){throw 'Home identity check failed'}
            if(@($networks|Where-Object {$_.Kind -eq 'Domains'}).Count -and (Test-Path (Join-Path $env:ProgramFiles 'homeNetbird\netbird-home.exe'))){
                $dnsDomains=(@($chosen|Where-Object {$_.Kind -eq 'Domains'}|ForEach-Object {$_.Target.Split(',')}|ForEach-Object {$_.Trim()}|Sort-Object -Unique)-join ',')
                $resultPath=Join-Path $env:TEMP ('homeNetbird-dns-'+[guid]::NewGuid()+'.json')
                $adminArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Update-HomeDNS.ps1')+'"'),'-ResultPath',('"'+$resultPath+'"'))
                if($dnsDomains){$adminArgs+=@('-Domains',('"'+$dnsDomains+'"'))}
                $admin=Start-Process powershell.exe -ArgumentList $adminArgs -Verb RunAs -WindowStyle Hidden -PassThru
                while(-not $admin.HasExited){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 100}
                $dnsResult=Get-Content $resultPath -Raw|ConvertFrom-Json;Remove-Item -LiteralPath $resultPath
                if(-not $dnsResult.ok){throw $dnsResult.error}
            }
            & $settings.BinaryPath --daemon-addr $settings.DaemonAddress routes deselect all
            if($LASTEXITCODE -ne 0){throw 'Could not clear previous route selections'}
            if($chosen.Count){
                $nativeArgs=@('--daemon-addr',$settings.DaemonAddress,'routes','select')+@($chosen.Id)
                & $settings.BinaryPath @nativeArgs
                if($LASTEXITCODE -ne 0){throw 'Could not select Home routes'}
            }
            & $settings.BinaryPath --daemon-addr $settings.DaemonAddress up --profile default --disable-client-routes=false --disable-auto-connect=false
            if($LASTEXITCODE -ne 0){throw 'Could not enable Home route processing'}
            $form.Close()
        }catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'homeNetbird')|Out-Null}
        finally{$apply.Enabled=$true}
    })
    try{[Windows.Forms.Application]::Run($form)}finally{$form.Dispose()}
}finally{$env:APPDATA=$originalAppData}
