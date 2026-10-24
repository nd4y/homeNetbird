param([ValidateSet('','up','down')][string]$InitialAction='')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'Home-Settings.ps1')
$settings = Get-HomeSettings
$ErrorActionPreference = 'Stop'
$mutex = New-Object Threading.Mutex($false, 'Local\NetBirdHomeTray')
if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); exit }
$stateDir = $settings.CacheDirectory
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$stateFile = Join-Path $stateDir 'tray-status.json'
$script:probe = $null
$script:nextProbe = [DateTime]::MinValue
$script:lastState = 'Starting'
function New-HomeIcon([string]$State) {
    $path = Join-Path $PSScriptRoot ('icons\home-'+$State+'.ico')
    return [Drawing.Icon]::new($path,[Windows.Forms.SystemInformation]::SmallIconSize)
}
$icons = @{Connected=(New-HomeIcon connected); Degraded=(New-HomeIcon degraded); Disconnected=(New-HomeIcon disconnected); Unavailable=(New-HomeIcon unavailable); Starting=(New-HomeIcon connecting); Connecting=(New-HomeIcon connecting)}
$tray = New-Object Windows.Forms.NotifyIcon
. (Join-Path $PSScriptRoot 'Home-Tray-Actions.ps1')
$tray.Icon = $icons.Starting
$tray.Text = 'Home NetBird: checking...'
$menu = New-Object Windows.Forms.ContextMenuStrip
$summary = $menu.Items.Add('Home NetBird: checking...')
$summary.Enabled = $false
$menu.Items.Add('-') | Out-Null
function Open-HomeWindow([string]$Mode) {
    Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Home-Tray-Action.ps1')+'"'),'-Mode',$Mode) -WindowStyle Normal
    $script:nextProbe = [DateTime]::MinValue
}
$connectItem = $menu.Items.Add('Connect Home'); $connectItem.Add_Click({Start-HomeAction up})
$disconnectItem = $menu.Items.Add('Disconnect Home'); $disconnectItem.Add_Click({Start-HomeAction down})
$item = $menu.Items.Add('Detailed status'); $item.Add_Click({Open-HomeWindow status})
$item = $menu.Items.Add('Routes'); $item.Add_Click({Open-HomeWindow routes})
$item = $menu.Items.Add('Choose Home routes'); $item.Add_Click({Start-Process powershell.exe -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Home-Routes.ps1')+'"')) -WindowStyle Hidden})
$item = $menu.Items.Add('Refresh'); $item.Add_Click({$script:nextProbe = [DateTime]::MinValue})
$menu.Items.Add('-') | Out-Null
$item = $menu.Items.Add('Exit indicator'); $item.Add_Click({[Windows.Forms.Application]::ExitThread()})
$tray.ContextMenuStrip = $menu
$tray.Add_DoubleClick({Open-HomeWindow status})
function Set-HomeState([string]$State,[string]$Text) {
    $tray.Icon = $icons[$State]
    $tray.Text = $Text.Substring(0,[Math]::Min(63,$Text.Length))
    $summary.Text = $Text
    if ($script:lastState -ne $State) {
        [IO.File]::WriteAllText($stateFile,(@{state=$State;summary=$Text;updated=(Get-Date -Format o);pid=$PID} | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    }
    $script:lastState = $State
}
function Start-HomeProbe {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $settings.BinaryPath
    $info.Arguments = '--daemon-addr "'+$settings.DaemonAddress+'" status --json'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.EnvironmentVariables['APPDATA'] = $stateDir
    $script:probe = New-Object Diagnostics.Process
    $script:probe.StartInfo = $info
    $script:probe.Start() | Out-Null
    $script:stdout = $script:probe.StandardOutput.ReadToEndAsync()
    $script:stderr = $script:probe.StandardError.ReadToEndAsync()
    $script:started = Get-Date
}
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    Update-HomeAction
    try {
        if ($null -ne $script:probe) {
            if ($script:probe.HasExited -and $script:stdout.IsCompleted -and $script:stderr.IsCompleted) {
                if ($script:probe.ExitCode -ne 0) { Set-HomeState Unavailable 'Home NetBird: daemon unavailable' }
                else {
                    $status = $script:stdout.Result | ConvertFrom-Json
                    if ($null -ne $script:homeAction -or $status.daemonStatus -eq 'Connecting') { Set-HomeState Connecting 'Home NetBird: connecting...' }
                    elseif ($status.daemonStatus -ne 'Connected') { Set-HomeState Disconnected 'Home NetBird: disconnected' }
                    elseif (-not $status.management.connected -or -not $status.signal.connected) { Set-HomeState Degraded 'Home NetBird: connection degraded' }
                    else { Set-HomeState Connected ("Home: {0} | peers {1}/{2}" -f $status.netbirdIp,$status.peers.connected,$status.peers.total) }
                }
                $script:probe.Dispose(); $script:probe = $null
                $script:nextProbe = (Get-Date).AddSeconds(10)
            } elseif (((Get-Date) - $script:started).TotalSeconds -gt 8) {
                $script:probe.Kill(); $script:probe.Dispose(); $script:probe = $null
                Set-HomeState Unavailable 'Home NetBird: status timeout'
                $script:nextProbe = (Get-Date).AddSeconds(10)
            }
        } elseif ((Get-Date) -ge $script:nextProbe) { Start-HomeProbe }
    } catch {
        if ($null -ne $script:probe) {
            try { if (-not $script:probe.HasExited) { $script:probe.Kill() } } catch {}
            $script:probe.Dispose(); $script:probe = $null
        }
        Set-HomeState Unavailable 'Home NetBird: status error'
        $script:nextProbe = (Get-Date).AddSeconds(10)
    }
})
try {
    $tray.Visible = $true
    $timer.Start()
    if($InitialAction){Start-HomeAction $InitialAction}
    [Windows.Forms.Application]::Run()
} finally {
    $timer.Stop(); $timer.Dispose()
    Stop-HomeAction
    if ($null -ne $script:probe) {
        try { if (-not $script:probe.HasExited) { $script:probe.Kill() } } catch {}
        $script:probe.Dispose()
    }
    $tray.Visible = $false; $tray.Dispose(); $menu.Dispose()
    foreach ($icon in $icons.Values) { $icon.Dispose() }
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
