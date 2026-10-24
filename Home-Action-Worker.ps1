# Runs inside a hidden worker. Native CLI output stays here, never in a toast or log.
function Invoke-HiddenHomeCli([string]$Arguments,[int]$TimeoutSeconds=10) {
    $info=[Diagnostics.ProcessStartInfo]::new()
    $info.FileName=$actionSettings.BinaryPath;$info.Arguments=$Arguments
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.EnvironmentVariables['APPDATA']=$actionSettings.CacheDirectory
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    try {
        $process.Start()|Out-Null
        $output=$process.StandardOutput.ReadToEndAsync();$errors=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit($TimeoutSeconds*1000)){$process.Kill();$process.WaitForExit();throw 'Home command timed out. Check the detailed status.'}
        $text=$output.GetAwaiter().GetResult();$null=$errors.GetAwaiter().GetResult()
        if($process.ExitCode -ne 0){throw ('Home command failed (exit '+$process.ExitCode+'). Check the detailed status.')}
        return $text
    }finally{$process.Dispose()}
}
function Get-HomeActionStatus([string]$Endpoint) {
    Invoke-HiddenHomeCli ('--daemon-addr "'+$Endpoint+'" status --json')|ConvertFrom-Json
}
function Invoke-HomeSilentAction([string]$Operation) {
    try {
        if($Operation -notin @('up','down')){throw 'Unsupported Home action'}
        if(Test-Path (Join-Path $PSScriptRoot 'Home-Settings.ps1')){
            . (Join-Path $PSScriptRoot 'Home-Settings.ps1')
            $actionSettings=Get-HomeSettings
        }else{
            $actionSettings=[pscustomobject]@{BinaryPath='C:\Program Files\Netbird\netbird.exe';DaemonAddress='tcp://127.0.0.1:41732';PrimaryAddress='tcp://127.0.0.1:41731';CacheDirectory=(Join-Path $env:LOCALAPPDATA 'NetBirdHomeCLI')}
        }
        New-Item -ItemType Directory -Path $actionSettings.CacheDirectory -Force|Out-Null
        if($Operation -eq 'up'){
            $primaryStatus=Get-HomeActionStatus $actionSettings.PrimaryAddress
            $homeStatus=Get-HomeActionStatus $actionSettings.DaemonAddress
            if($primaryStatus.netbirdIp -and $homeStatus.netbirdIp -and ($primaryStatus.netbirdIp.Split('/')[0] -eq $homeStatus.netbirdIp.Split('/')[0])){throw 'The primary client uses the Home identity. Select another primary profile first.'}
        }
        $arguments='--daemon-addr "'+$actionSettings.DaemonAddress+'" '+$Operation
        if($Operation -eq 'up'){$arguments+=' --profile default --disable-auto-connect=false'}
        $null=Invoke-HiddenHomeCli $arguments 120
        $status=Get-HomeActionStatus $actionSettings.DaemonAddress
        $connected=$status.daemonStatus -eq 'Connected' -and $status.management.connected
        if($Operation -eq 'up' -and -not $connected){throw 'Home is not connected yet. Check the detailed status.'}
        if($Operation -eq 'down' -and $connected){throw 'Home is still connected. Check the detailed status.'}
        [pscustomobject]@{ok=$true;operation=$Operation;message=$(if($Operation -eq 'up'){'Home connected.'}else{'Home disconnected.'})}
    }catch{[pscustomobject]@{ok=$false;operation=$Operation;message=$_.Exception.Message}}
}
