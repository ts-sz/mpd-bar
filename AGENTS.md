# AGENTS.md

Operational manual for AI coding agents working on this repository.

## What this product is

A macOS 13+ menu bar app (SwiftUI `MenuBarExtra`, window style) that remote-controls a
web radio playlist on a music server, distributed as a Homebrew formula that builds
from source.

Design properties to preserve:

1. **Two backends behind one protocol.** `PlayerBackend` (in `MPDBarCore/Models.swift`) is
   the only thing the UI talks to. `MopidyBackend` speaks Mopidy JSON-RPC over HTTP;
   `MPDBackend` speaks the MPD text protocol over TCP. A new feature lands in the protocol
   and in both backends, or is shown only where the backend supports it.
2. **Stations come from the server.** The station list is a stored playlist on the server,
   read at runtime. The app holds no station data.
3. **Secrets live in the login Keychain**, service `mpd-bar`, accounts `cf-client-id`,
   `cf-client-secret`, `mpd-password`. Settings that are not secret live in UserDefaults
   (`settings.v1`). Logs, errors and the probe output carry status codes and messages only.
4. **Apple frameworks only.** SwiftUI, Foundation, Network, Security. The package has no
   dependencies, which keeps the Homebrew build fast and offline-safe.
5. **Native look.** System colors, accent color, SF Symbols, 320 pt wide panel, English UI.
6. **Shared players stay as they were.** Real servers are often shared rooms. Anything that
   plays, stops or changes volume during a test runs against a test server, or records the
   state first and restores it after.

## Layout

```
Package.swift                  SwiftPM, macOS 13, three targets
Sources/MPDBarCore/            backends, models, settings, Keychain (no UI)
  Models.swift                 Station, PlayerStatus, PlayerError, PlayerBackend protocol
  Settings.swift               PlayerSettings, Keychain, Credentials, BackendFactory
  MopidyBackend.swift          JSON-RPC 2.0 batches over URLSession
  MPDBackend.swift             MPDClient (one short TCP session per command list) + MPDBackend
Sources/MPDBar/                the app: AppModel (polling, actions), views
Sources/MPDBarProbe/           mpdbar-probe, command-line check used by CI
Resources/Info.plist           bundle metadata (LSUIElement, macOS 13)
scripts/bundle.sh              build MPDBar.app from source, optional --install
Formula/mpd-bar.rb             Homebrew formula (this repo doubles as the tap)
.github/workflows/ci.yml       build, MPD integration test, formula install from HEAD
```

## Build and test

```bash
swift build -c release                  # all targets
scripts/bundle.sh                       # build/MPDBar.app
scripts/bundle.sh --install             # copy to ~/Applications and launch
"$(swift build -c release --show-bin-path)/mpdbar-probe" --mpd 127.0.0.1:6600 --playlist NAME
```

CI (`macos-14`) builds everything, starts a local MPD with a null audio output and a
two-station playlist, runs the probe read-only, then with `--write`, checks the
unknown-playlist error, and installs the formula from HEAD. A change is done when CI is green.

Polling: the app refreshes every 4 s while the panel is open and every 30 s otherwise.
Mopidy refresh is one HTTP request (JSON-RPC batch); MPD refresh is one TCP session
(`status` + `currentsong` in a command list).

## Release

1. Bump `Version.string` in `Models.swift` and `CFBundleShortVersionString` in `Resources/Info.plist`.
2. Commit, push, wait for CI green, then tag `vX.Y.Z` and push the tag.
3. Compute the tarball checksum:
   `curl -sL https://github.com/ts-sz/mpd-bar/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256`
4. Update `url` and `sha256` in `Formula/mpd-bar.rb`, commit, push.
5. Verify on a Mac: `brew update && brew upgrade mpd-bar && brew test mpd-bar`.

## Conventions

- Swift 5 language mode, everything UI-facing and every backend is `@MainActor`.
  Network callbacks bridge to async with `withCheckedThrowingContinuation` and `OnceFlag`.
- Errors surface as `PlayerError` with a short English sentence the panel can show as is.
- Commit messages in English, imperative mood, body explaining why.
- `CLAUDE.md` and `.github/copilot-instructions.md` point here; this file is the single source.
