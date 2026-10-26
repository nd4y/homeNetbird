param([Parameter(Mandatory)][string]$SourceDirectory)
$ErrorActionPreference = 'Stop'
function Replace-Required([string]$Path,[string]$Old,[string]$New) {
    $text = [IO.File]::ReadAllText($Path)
    if (-not $text.Contains($Old)) { throw "Upstream patch anchor missing in $Path" }
    [IO.File]::WriteAllText($Path,$text.Replace($Old,$New),[Text.UTF8Encoding]::new($false))
}
$dns = Join-Path $SourceDirectory 'client\internal\dns\host_windows.go'
Replace-Required $dns 'NetBird-Match' 'NetBird-Home-Match'
Replace-Required $dns '"fmt"' "`"fmt`"`n`t`"os`""
$anchor = 'func (r *registryConfigurator) applyDNSConfig(config HostDNSConfig, stateManager *statemanager.Manager) error {'
$replacement = @'
func (r *registryConfigurator) applyDNSConfig(config HostDNSConfig, stateManager *statemanager.Manager) error {
    // Home owns only explicitly matched DNS namespaces, never general DNS.
    config.RouteAll = false
    for _, name := range strings.Split(os.Getenv("NB_DUAL_EXTRA_DOMAINS"), ",") {
        name = strings.TrimSpace(strings.TrimPrefix(name, "*."))
        if name != "" {
            config.Domains = append(config.Domains, DomainConfig{Domain: name, MatchOnly: true})
        }
    }
'@
Replace-Required $dns $anchor $replacement
$firewall = Join-Path $SourceDirectory 'client\firewall\uspfilter\allow_netbird_windows.go'
Replace-Required $firewall 'firewallRuleName        = "Netbird"' 'firewallRuleName        = "NetbirdHome"'
# Upstream already exposes CustomWindowsGUIDString; the build assigns a distinct GUID.
$signal=Join-Path $SourceDirectory 'shared\signal\client\grpc.go'
Replace-Required $signal "type GrpcClient struct {" "type GrpcClient struct {`n homeRecovery homeSignalRecovery`n homeTLS bool"
Replace-Required $signal 'realClient:            proto.NewSignalExchangeClient(conn),' "realClient:            proto.NewSignalExchangeClient(conn),`n homeTLS: tlsEnabled,"
Replace-Required $signal "`tif err != nil {`n`t`tc.notifyDisconnected(err)`n`t`tlog.Warnf(`"health check returned: %s`", err)" "`tc.observeHomeSignalHealth(err)`n`tif err != nil {`n`t`tc.notifyDisconnected(err)`n`t`tlog.Warnf(`"health check returned: %s`", err)"
Replace-Required $signal "`t`tcancel()`n`n`t`tif s, ok := status.FromError(err);" "`t`tcancel()`n`t`tc.observeHomeSignalHealth(err)`n`n`t`tif s, ok := status.FromError(err);"
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'daemon\home_signal_recovery.go'),(Join-Path $PSScriptRoot 'daemon\home_signal_recovery_test.go') -Destination (Join-Path $SourceDirectory 'shared\signal\client') -Force
