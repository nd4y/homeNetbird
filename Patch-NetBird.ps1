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
