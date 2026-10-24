$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$project=Split-Path $PSScriptRoot
$temp=Join-Path $env:TEMP ('homeNetbird-actions-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $temp|Out-Null
$source=@'
using System; using System.IO; using System.Threading;
class FakeCli {
    static int Main(string[] args) {
        if(Environment.GetEnvironmentVariable("HOME_TRAY_TEST_SLEEP")=="1") Thread.Sleep(10000);
        if(Environment.GetEnvironmentVariable("HOME_TRAY_TEST_FAIL")=="1") { Console.Error.WriteLine("test-sensitive-output"); return 7; }
        string state=Environment.GetEnvironmentVariable("HOME_TRAY_TEST_STATE");
        if(Array.IndexOf(args,"up")>=0) { File.WriteAllText(state,"connected"); return 0; }
        if(Array.IndexOf(args,"down")>=0) { File.WriteAllText(state,"disconnected"); return 0; }
        bool primary=Array.IndexOf(args,"tcp://127.0.0.1:41731")>=0;
        bool connected=primary || !File.Exists(state) || File.ReadAllText(state)=="connected";
        string flag=connected ? "true" : "false";
        Console.WriteLine("{\"daemonStatus\":\""+(connected?"Connected":"Idle")+"\",\"management\":{\"connected\":"+flag+"},\"signal\":{\"connected\":"+flag+"},\"netbirdIp\":\""+(primary?"100.64.1.1/16":"100.65.1.1/16")+"\"}");
        return 0;
    }
}
'@
$cs=Join-Path $temp 'FakeCli.cs';$exe=Join-Path $temp 'FakeCli.exe'
[IO.File]::WriteAllText($cs,$source)
& (Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /target:exe ('/out:'+$exe) $cs
if($LASTEXITCODE -ne 0){throw 'Fixture compilation failed'}
$names=@('NETBIRD_HOME_BINARY','NETBIRD_HOME_CACHE','HOME_TRAY_TEST_STATE','HOME_TRAY_TEST_FAIL','HOME_TRAY_TEST_SLEEP')
$previous=@{};foreach($name in $names){$previous[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
$script:notifications=[Collections.ArrayList]::new()
$tray=[pscustomobject]@{BalloonTipTitle='';BalloonTipText='';BalloonTipIcon=[Windows.Forms.ToolTipIcon]::None}
$tray|Add-Member -MemberType ScriptMethod -Name ShowBalloonTip -Value {param($Duration);$script:notifications.Add([pscustomobject]@{text=$this.BalloonTipText;kind=$this.BalloonTipIcon})|Out-Null}
$connectItem=[pscustomobject]@{Enabled=$true};$disconnectItem=[pscustomobject]@{Enabled=$true}
. (Join-Path $project 'Home-Tray-Actions.ps1')
function Complete-Action {
    $deadline=(Get-Date).AddSeconds(15)
    while($null -ne $script:homeAction -and (Get-Date) -lt $deadline){Update-HomeAction;Start-Sleep -Milliseconds 100}
    if($null -ne $script:homeAction){throw 'Action did not finish'}
    if(-not $connectItem.Enabled -or -not $disconnectItem.Enabled){throw 'Menu remained disabled'}
}
try {
    $env:NETBIRD_HOME_BINARY=$exe;$env:NETBIRD_HOME_CACHE=$temp;$env:HOME_TRAY_TEST_STATE=Join-Path $temp 'state.txt'
    Start-HomeAction up
    if(-not $script:homeAction.process.StartInfo.CreateNoWindow -or $script:homeAction.process.StartInfo.UseShellExecute){throw 'Worker can open a console'}
    $firstPID=$script:homeAction.process.Id;Start-HomeAction down
    if($script:homeAction.process.Id -ne $firstPID){throw 'Duplicate action launched'}
    Complete-Action
    if($notifications[-1].text -ne 'Home connected.'){throw 'Connect result not notified'}
    Start-HomeAction down;Complete-Action
    if($notifications[-1].text -ne 'Home disconnected.'){throw 'Disconnect result not notified'}
    $env:HOME_TRAY_TEST_FAIL='1';Start-HomeAction up;Complete-Action
    if($notifications[-1].kind -ne [Windows.Forms.ToolTipIcon]::Error -or $notifications[-1].text -match 'test-sensitive-output'){throw 'Failure handling leaked native output or failed to notify'}
    $env:HOME_TRAY_TEST_FAIL=$null;$env:HOME_TRAY_TEST_SLEEP='1';Start-HomeAction up
    $script:homeAction.started=(Get-Date).AddSeconds(-181);Update-HomeAction
    if($null -ne $script:homeAction -or $notifications[-1].kind -ne [Windows.Forms.ToolTipIcon]::Warning){throw 'Timeout handling failed'}
    'PASS: hidden worker, Connect/Disconnect notifications, duplicate suppression, errors, timeout, menu recovery. No real VPN operations.'
}finally{
    Stop-HomeAction
    foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$previous[$name],'Process')}
}
