function Get-HomeSettings {
    $binary = if ($env:NETBIRD_HOME_BINARY) { $env:NETBIRD_HOME_BINARY } else { Join-Path $env:ProgramFiles 'Netbird\netbird.exe' }
    $endpoint = if ($env:NETBIRD_HOME_DAEMON_ADDR) { $env:NETBIRD_HOME_DAEMON_ADDR } else { 'tcp://127.0.0.1:41732' }
    $primary = if ($env:NETBIRD_PRIMARY_DAEMON_ADDR) { $env:NETBIRD_PRIMARY_DAEMON_ADDR } else { 'tcp://127.0.0.1:41731' }
    $cache = if ($env:NETBIRD_HOME_CACHE) { $env:NETBIRD_HOME_CACHE } else { Join-Path $env:LOCALAPPDATA 'NetBirdHomeCLI' }
    foreach ($address in @($endpoint,$primary)) {
        if ($address -notmatch '^tcp://(127\.0\.0\.1|localhost):\d{1,5}$') { throw 'Daemon addresses must be local TCP endpoints, for example tcp://127.0.0.1:41732.' }
    }
    [pscustomobject]@{BinaryPath=$binary;DaemonAddress=$endpoint;PrimaryAddress=$primary;CacheDirectory=$cache}
}
