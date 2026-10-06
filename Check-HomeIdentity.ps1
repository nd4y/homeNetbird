$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Home-Settings.ps1')
$settings = Get-HomeSettings
$env:APPDATA = $settings.CacheDirectory
try {
    # Read status only. Never switch the primary GUI profile.
    $primary = & $settings.BinaryPath --daemon-addr $settings.PrimaryAddress status --json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'Could not check the primary client identity.' }
    $homeStatus = & $settings.BinaryPath --daemon-addr $settings.DaemonAddress status --json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'Could not check the Home client identity.' }
    if ($primary.netbirdIp -and $homeStatus.netbirdIp -and ($primary.netbirdIp.Split('/')[0] -eq $homeStatus.netbirdIp.Split('/')[0])) {
        throw 'The primary client is using the same identity as Home. Select another profile in the primary GUI before connecting Home.'
    }
    exit 0
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
