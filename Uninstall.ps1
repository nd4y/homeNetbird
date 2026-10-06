param([switch]$RemoveDaemon)
$ErrorActionPreference = 'Stop'
if($RemoveDaemon){
    $process=Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Remove-Service.ps1')+'"')) -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if($process.ExitCode -ne 0){throw 'Daemon removal failed; tray installation retained.'}
}
$directory = [IO.Path]::GetFullPath($PSScriptRoot)
$userPath = [Environment]::GetEnvironmentVariable('Path','User')
$remaining = @($userPath -split ';' | Where-Object {$_ -and $_.TrimEnd('\') -ne $directory.TrimEnd('\')})
[Environment]::SetEnvironmentVariable('Path',($remaining -join ';'),'User')
$shell = New-Object -ComObject WScript.Shell
foreach ($folder in @([Environment]::GetFolderPath('Startup'),[Environment]::GetFolderPath('Desktop'))) {
    $link = Join-Path $folder 'Home NetBird Tray.lnk'
    if (Test-Path -LiteralPath $link) {
        $shortcut = $shell.CreateShortcut($link)
        if ($shortcut.Arguments.Contains((Join-Path $directory 'Home-Tray.ps1'))) { Remove-Item -LiteralPath $link }
    }
}
Write-Host 'Startup/Desktop shortcuts and this directory PATH entry removed. Exit the indicator via its menu; then remove the installation folder if desired. VPN services and configuration were not changed.'
