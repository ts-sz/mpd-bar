# MPD Bar

[![CI](https://github.com/ts-sz/mpd-bar/actions/workflows/ci.yml/badge.svg)](https://github.com/ts-sz/mpd-bar/actions/workflows/ci.yml)
[![Secret scan](https://github.com/ts-sz/mpd-bar/actions/workflows/secrets.yml/badge.svg)](https://github.com/ts-sz/mpd-bar/actions/workflows/secrets.yml)
[![CodeQL](https://github.com/ts-sz/mpd-bar/actions/workflows/codeql.yml/badge.svg)](https://github.com/ts-sz/mpd-bar/actions/workflows/codeql.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/ts-sz/mpd-bar/badge)](https://scorecard.dev/viewer/?uri=github.com/ts-sz/mpd-bar)
[![Release](https://img.shields.io/github/v/release/ts-sz/mpd-bar)](https://github.com/ts-sz/mpd-bar/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A macOS menu bar remote for a web radio playlist on an **MPD** or **Mopidy** server.
Click the radio icon at the top right of the screen: now playing, play / pause / stop,
previous and next station, volume, and one button per station.

- **Mopidy over HTTP** (JSON-RPC, `/mopidy/rpc`): direct, or behind **Cloudflare Access**
  with a service token.
- **MPD over TCP** (native protocol, port 6600): direct, on your LAN or a VPN such as Tailscale.
- Native SwiftUI, light and dark mode, no Dock icon. macOS 13 Ventura or later,
  Apple silicon and Intel.
- One JSON config file, `~/.config/mpd-bar/config.json`, read by the app and the probe and
  reloaded on save. It is kept private to your user (mode 600).
- No telemetry: the app talks only to the server you configure.

## Install

### Homebrew (recommended)

```bash
brew tap ts-sz/mpd-bar https://github.com/ts-sz/mpd-bar
brew install ts-sz/mpd-bar/mpd-bar
brew services start mpd-bar      # start now and at every login
```

Homebrew builds the app on your Mac from source, so it needs the Xcode Command Line Tools
(`xcode-select --install`). A locally built app opens without any Gatekeeper prompt.

To open it once without starting it at login, run `mpd-bar` instead of `brew services start`.

### Upgrade

```bash
brew update
brew upgrade mpd-bar
brew services restart mpd-bar
```

The config file is kept across upgrades.

### Download from the release page

Every [release](https://github.com/ts-sz/mpd-bar/releases/latest) carries a universal app zip,
the command-line probe and a `SHA256SUMS` file. The app is ad-hoc signed, not notarized, so
remove the quarantine flag once after unzipping:

```bash
shasum -a 256 -c SHA256SUMS --ignore-missing
unzip MPDBar-*-macos-universal.zip -d ~/Applications
xattr -dr com.apple.quarantine ~/Applications/MPDBar.app
open ~/Applications/MPDBar.app
```

## First run

Create the config file, edit it, check it:

```bash
mpdbar-probe init                           # writes ~/.config/mpd-bar/config.json (mode 600)
open -t ~/.config/mpd-bar/config.json       # or any editor
mpdbar-probe                                # tests the server the file points to
```

The app offers the same from its Settings panel (**Create config file**, **Open**, **Test**)
and reloads the file whenever it changes. `MPDBAR_CONFIG=/path/to/file.json` points both
the app (when launched from a shell) and the probe elsewhere.

## Config file

Mopidy behind Cloudflare Access:

```json
{
  "backend": "mopidy",
  "playlist": "radios",
  "mopidy": {
    "url": "https://music.example.com",
    "cloudflare_access": {
      "client_id": "....access",
      "client_secret": "..."
    }
  }
}
```

Mopidy direct: drop `cloudflare_access` and use `"url": "http://music.local:6680"`.

MPD:

```json
{
  "backend": "mpd",
  "playlist": "radios",
  "mpd": { "host": "music.local", "port": 6600, "password": "" }
}
```

| Key | Meaning |
|---|---|
| `backend` | `mopidy` or `mpd` |
| `playlist` | name of a stored playlist on the server (`radios`), or for Mopidy a URI (`m3u:radios.m3u8`). Each entry becomes a station button, in playlist order |
| `mopidy.url` | base URL of Mopidy; the app calls `<url>/mopidy/rpc` |
| `mopidy.cloudflare_access` | optional, service token `client_id` and `client_secret` |
| `mpd.host`, `mpd.port` | MPD address, port defaults to 6600 |
| `mpd.password` | optional, empty for none |

Both `mopidy` and `mpd` sections may be present; `backend` picks one. A file that does not
parse or misses a key shows the exact key in the panel and in `mpdbar-probe`.

### Cloudflare Access service token

In Cloudflare Zero Trust, create a service token (Access, Service Auth), then add a policy
with the action **Service Auth** that includes that token to the Access application
protecting your Mopidy host. A dedicated token per Mac lets you revoke one machine alone.

### MPD through a gateway

Cloudflare Access protects HTTP, not the raw MPD protocol. Reach MPD directly on your LAN
or over a VPN (Tailscale, WireGuard). MPD sends its password in clear text: keep it off the
open internet.

## Command-line probe

`mpdbar-probe` checks a server without the UI. It is read-only unless `--write` is given.
Without arguments it reads the config file, exactly like the app.

```bash
mpdbar-probe                                # the server in ~/.config/mpd-bar/config.json
mpdbar-probe --config ./other.json
mpdbar-probe --mpd music.local:6600 --playlist radios
mpdbar-probe --mopidy http://music.local:6680 --playlist radios

# Mopidy behind Cloudflare Access
CF_ACCESS_CLIENT_ID=... CF_ACCESS_CLIENT_SECRET=... \
  mpdbar-probe --mopidy https://music.example.com --playlist radios

# Plays the first station, sets the volume to 37, then stops: use on a test server
mpdbar-probe --mpd localhost:6600 --playlist radios --write
```

## Troubleshooting

| Message in the panel | Cause |
|---|---|
| `Config error: missing key "mopidy.url".` | The file does not match the format above; the message names the key |
| `Access denied. Check the Cloudflare Access client ID and secret.` | Wrong token, or the token is not in a Service Auth policy of the Access application |
| `Playlist "x" not found. Available: ...` | The name does not match a stored playlist; pick one from the list |
| `Server unreachable (...)` | Wrong host or port, server down, or no VPN |
| `Not an MPD server.` | The port answers, but not with MPD (wrong port) |

## Build from source

```bash
git clone https://github.com/ts-sz/mpd-bar && cd mpd-bar
scripts/bundle.sh --install            # build, copy to ~/Applications, open
UNIVERSAL=1 scripts/bundle.sh          # universal binaries, as releases do
```

## Uninstall

```bash
brew services stop mpd-bar
brew uninstall mpd-bar
brew untap ts-sz/mpd-bar
rm -r ~/.config/mpd-bar
```

Versions before 0.2.0 kept settings in the Keychain and UserDefaults. To remove those leftovers:

```bash
for a in cf-client-id cf-client-secret mpd-password; do security delete-generic-password -s mpd-bar -a "$a"; done
defaults delete io.github.ts-sz.mpd-bar
```

## Project

- [CHANGELOG.md](CHANGELOG.md): what changed in each version.
- [CONTRIBUTING.md](CONTRIBUTING.md): development setup, tests, pull requests.
- [SECURITY.md](SECURITY.md): how to report a vulnerability, how secrets are handled.
- [AGENTS.md](AGENTS.md): technical manual for coding agents (architecture, build, release).

## License

[MIT](LICENSE)
