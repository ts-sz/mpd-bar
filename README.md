# MPD Bar

A macOS menu bar remote for a web radio playlist on an **MPD** or **Mopidy** server.
Click the radio icon at the top right of the screen: now playing, play / pause / stop,
previous and next station, volume, and one button per station.

- **Mopidy over HTTP** (JSON-RPC, `/mopidy/rpc`): direct, or behind **Cloudflare Access**
  with a service token.
- **MPD over TCP** (native protocol, port 6600): direct, on your LAN or a VPN such as Tailscale.
- Native SwiftUI, follows light and dark mode, no Dock icon. macOS 13 Ventura or later.
- Secrets (Cloudflare service token, MPD password) are stored in the login Keychain.

## Install with Homebrew

```bash
brew tap ts-sz/mpd-bar https://github.com/ts-sz/mpd-bar
brew install ts-sz/mpd-bar/mpd-bar
brew services start mpd-bar      # start now and at every login
```

Homebrew builds the app on your Mac from source, so it needs the Xcode Command Line Tools
(`xcode-select --install`). A locally built app runs without Gatekeeper prompts.

Update with `brew upgrade mpd-bar`, then `brew services restart mpd-bar`.

## First run

Click the radio icon. The Settings panel opens until a server and a playlist are set.

| Server | Fields |
|---|---|
| Mopidy, direct | URL such as `http://music.local:6680`, access **Direct** |
| Mopidy, Cloudflare Access | URL such as `https://music.example.com`, access **Cloudflare Access**, then the service token Client ID and Client Secret |
| MPD | Host, port (6600), optional password |

**Playlist** is the name of a stored playlist on the server (`radios`), or for Mopidy a
playlist URI (`m3u:radios.m3u8`). Each entry of the playlist becomes a station button,
in playlist order.

**Test** checks the connection and counts the stations; **Save** stores the settings
and loads the stations.

### Cloudflare Access service token

In Cloudflare Zero Trust, create a service token (Access, Service Auth), then add a policy
with the action **Service Auth** that includes that token to the Access application
protecting your Mopidy host. A dedicated token per Mac lets you revoke one machine alone.

## Command-line probe

`mpdbar-probe` checks a server without the UI. It is read-only unless `--write` is given.

```bash
mpdbar-probe --mpd music.local:6600 --playlist radios
mpdbar-probe --mopidy http://music.local:6680 --playlist radios

# Mopidy behind Cloudflare Access
CF_ACCESS_CLIENT_ID=... CF_ACCESS_CLIENT_SECRET=... \
  mpdbar-probe --mopidy https://music.example.com --playlist radios

# Plays the first station, sets the volume to 37, then stops: use on a test server
mpdbar-probe --mpd localhost:6600 --playlist radios --write
```

## Build from source

```bash
git clone https://github.com/ts-sz/mpd-bar && cd mpd-bar
scripts/bundle.sh --install      # builds build/MPDBar.app, copies it to ~/Applications, opens it
```

## Uninstall

```bash
brew services stop mpd-bar
brew uninstall mpd-bar
security delete-generic-password -s mpd-bar -a cf-client-id
security delete-generic-password -s mpd-bar -a cf-client-secret
security delete-generic-password -s mpd-bar -a mpd-password
defaults delete io.github.ts-sz.mpd-bar
```

## License

MIT
