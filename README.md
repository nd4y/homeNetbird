# homeNetbird

An independent Windows tray indicator for your Home NetBird connection, with an Aurora icon theme and a CLI that forwards native NetBird commands.

![homeNetbird - Aurora icon theme](icons/home-preview.png)

Keep the official NetBird GUI for your primary network and give an existing secondary daemon its own status indicator. Hover to see its IP and connected peer count, double-click for detailed status, or use the context menu to connect, disconnect and list routes.

## Status colors

| Icon | Meaning |
|---|---|
| Cyan / electric blue / violet | Connected, Management and Signal reachable |
| Gold / coral | Connected, with a Management or Signal problem |
| Muted blue / rose | Disconnected |
| Slate | Starting, daemon unavailable, or status request failed |

The icon preserves NetBird's bird silhouette with a new Aurora color treatment. ICO files contain 16, 20, 24, 32, 48 and 64 px frames. The preview above is the same artwork used by the indicator.

## Requirements

- Windows with Windows PowerShell 5.1 and an interactive desktop session.
- Installed NetBird CLI, tested with version 0.71.4.
- An **already configured, running secondary NetBird daemon**, default endpoint `tcp://127.0.0.1:41732`.
- Its intended profile selected in the isolated Home CLI cache before using `up`.

This project does not install a second VPN service or provide a patched NetBird binary. Running two clients safely also requires independent state, interfaces, ports and compatible DNS/firewall/route handling. Stock NetBird profile switching alone does not create concurrent networks. See [NetBird issue #446](https://github.com/netbirdio/netbird/issues/446) for context.

## Install

Download or clone this repository, then run from its directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

The installer copies the runtime to `%LOCALAPPDATA%\Programs\NetBirdHomeTray`, adds a user PATH entry, creates Desktop and Startup shortcuts, and starts the indicator. It does not require administrator rights or change VPN services. Open a fresh terminal to use the CLI.

Optional switches: `-NoStartup`, `-NoDesktop`, `-NoPath`, `-NoLaunch`, and `-Destination <directory>`.

To run directly without installing:

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File .\Home-Tray.ps1
```

Windows may put the icon in the tray overflow. Drag it into the visible notification area if needed. Only one indicator runs per Windows session. Exiting the indicator leaves the VPN connected.

## CLI

```powershell
homenetbird up
homenetbird down
homenetbird status -d
homenetbird status --json | ConvertFrom-Json
homenetbird routes list
homenetbird up --help
```

Arguments, subcommands, output and exit codes pass through to the native CLI. No arguments means `status`. The wrapper selects the secondary daemon and isolates its CLI `APPDATA` so it does not change the primary GUI's cached profile. `up` uses the last selected Home profile; caller flags retain their native meaning.

For a conventional secondary `default` profile, explicitly connect with:

```powershell
homenetbird up --profile default
```

Before a first-argument `up`, a read-only preflight checks the primary and secondary daemon IPs and rejects a matching identity. This is a basic IP comparison, not a complete duplicate-identity detector; both status endpoints must be available. Configuration-changing native commands and explicit daemon flags should be used deliberately.

## Configuration

Both tray and CLI use these environment variables:

| Variable | Default |
|---|---|
| `NETBIRD_HOME_BINARY` | `%ProgramFiles%\Netbird\netbird.exe` |
| `NETBIRD_HOME_DAEMON_ADDR` | `tcp://127.0.0.1:41732` |
| `NETBIRD_PRIMARY_DAEMON_ADDR` | `tcp://127.0.0.1:41731` |
| `NETBIRD_HOME_CACHE` | `%LOCALAPPDATA%\NetBirdHomeCLI` |

Use local TCP daemon endpoints. Set user environment variables persistently if they must apply after sign-in, then restart the indicator. For a temporary session:

```powershell
$env:NETBIRD_HOME_DAEMON_ADDR = 'tcp://127.0.0.1:41732'
.\homenetbird.cmd status -d
```

## How it works and limitations

The tray polls `status --json` roughly every 10 seconds. Requests run hidden with asynchronous output reads and an 8-second timeout, keeping the menu responsive. A minimal last-transition record is written to the Home cache as `tray-status.json`; full peer details and keys are not stored there.

Connected status describes the daemon/control plane. It does not prove that every peer or service is reachable. DNS and routes remain the responsibility of the VPN configuration: Windows routes by destination IP, so identical IPs in two networks need explicit routing/address translation or separate network stacks. The indicator does not arbitrate conflicting DNS namespaces or routes.

Live checks covered connected status, native detailed and JSON output, exit codes, ICO loading at every included size, and duplicate-launch prevention. Interactive menu actions and next-sign-in startup still need wider user testing.

## Uninstall

Exit the indicator from its menu, then run `Uninstall.ps1` in the installed directory. It removes this installation's shortcuts and PATH entry. Delete the installation folder afterwards if desired. The isolated CLI cache and VPN configuration are retained.

## Rebuild the artwork

Node.js is only needed to regenerate the committed icons, not to run the tray:

```powershell
npm install
npm run build:icons
```

## License

Project scripts: MIT. NetBird-derived icon geometry: BSD 3-Clause, with attribution in [NOTICE](NOTICE) and the upstream license in [NETBIRD-LICENSE](NETBIRD-LICENSE). This is an independent community project with no NetBird endorsement.
