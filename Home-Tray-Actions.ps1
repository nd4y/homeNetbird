# Asynchronous Connect/Disconnect, owned by the existing tray icon.
$script:homeAction=$null
function Show-HomeActionNotification([string]$Message,[string]$Kind='Info') {
    $tray.BalloonTipTitle='Home NetBird'
    $tray.BalloonTipText=$Message
    $tray.BalloonTipIcon=[Windows.Forms.ToolTipIcon]::$Kind
    $tray.ShowBalloonTip(4000)
}
function Start-HomeAction([string]$Mode) {
    if($null -ne $script:homeAction){return}
    if($Mode -notin @('up','down')){throw 'Unsupported Home action'}
    try {
        $info=[Diagnostics.ProcessStartInfo]::new()
        $info.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $info.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'Home-Tray-Action.ps1')+'" -Mode '+$Mode+' -SilentAction'
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true
        $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $process=[Diagnostics.Process]::new();$process.StartInfo=$info
        $process.Start()|Out-Null
        $script:homeAction=@{process=$process;stdout=$process.StandardOutput.ReadToEndAsync();stderr=$process.StandardError.ReadToEndAsync();started=(Get-Date);mode=$Mode}
        $connectItem.Enabled=$false;$disconnectItem.Enabled=$false
        if(Get-Command Set-HomeState -ErrorAction SilentlyContinue){Set-HomeState Connecting 'Home NetBird: working...'}
        Show-HomeActionNotification $(if($Mode -eq 'up'){'Connecting Home...'}else{'Disconnecting Home...'})
    }catch{
        if($null -ne $process){$process.Dispose()}
        $script:homeAction=$null
        $connectItem.Enabled=$true;$disconnectItem.Enabled=$true
        Show-HomeActionNotification 'Could not start the Home command.' 'Error'
    }
}
function Stop-HomeAction {
    if($null -eq $script:homeAction){return}
    $process=$script:homeAction.process
    if(-not $process.HasExited){
        # Terminate only this owned worker and its native CLI child, never the daemon.
        $killInfo=[Diagnostics.ProcessStartInfo]::new()
        $killInfo.FileName=Join-Path $env:SystemRoot 'System32\taskkill.exe'
        $killInfo.Arguments='/PID '+$process.Id+' /T /F'
        $killInfo.UseShellExecute=$false;$killInfo.CreateNoWindow=$true
        $killer=[Diagnostics.Process]::Start($killInfo);$killer.WaitForExit(3000)|Out-Null;$killer.Dispose()
    }
    $process.Dispose();$script:homeAction=$null
    $connectItem.Enabled=$true;$disconnectItem.Enabled=$true
    $script:nextProbe=[DateTime]::MinValue
}
function Update-HomeAction {
    if($null -eq $script:homeAction){return}
    $action=$script:homeAction
    if($action.process.HasExited -and $action.stdout.IsCompleted -and $action.stderr.IsCompleted){
        try {
            $result=$action.stdout.Result|ConvertFrom-Json
            if($result.ok -and $action.process.ExitCode -eq 0){Show-HomeActionNotification $result.message}
            else{Show-HomeActionNotification $(if($result.message){$result.message}else{'Home command failed.'}) 'Error'}
        }catch{Show-HomeActionNotification 'Home command failed. Check the detailed status.' 'Error'}
        finally{Stop-HomeAction}
    }elseif(((Get-Date)-$action.started).TotalSeconds -gt 180){
        Stop-HomeAction
        Show-HomeActionNotification 'Home command timed out. Check the detailed status.' 'Warning'
    }
}
