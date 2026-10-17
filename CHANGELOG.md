# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-10-16

### Added
- The Settings panel now edits the config file in the app: a connection mode picker (Cloudflare
  Access, Mopidy direct, MPD) prefills the right shape, every field is editable, and **Save**
  writes the file (mode 600, atomic) and reloads it. The file stays the single source of truth.
- A playlist browser fetched from the server with the draft's own settings: searchable list,
  the selected playlist's track count, duplicates saved as their unambiguous URI.
- **Test** now checks the draft as typed, before saving.

## [0.3.2] - 2026-10-16

### Changed
- One menu bar icon for every state: the radio symbol, with a small badge for play, pause or
  mute, and no badge when stopped. It replaces the switch between two different symbols. The
  panel's now-playing tile uses the same icon.
- `mpdbar-probe render-icons DIR` writes the icons as PNG; CI publishes them as an artifact.

## [0.3.1] - 2026-10-16

### Fixed
- A muted Mopidy server showed **Playing** with no hint why nothing was heard. The status now
  reads **Playing, muted** in red, the speaker icon becomes a mute toggle (Mopidy only; MPD has
  no mute), and pressing play on a station or resuming unmutes first. `mpdbar-probe` prints
  `MUTED` in its status line.

## [0.3.0] - 2026-10-16

### Added
- `mpdbar-probe playlists [WORD]` lists the stored playlists on the server (name and Mopidy URI),
  with the config file's settings and token, or with `--mopidy` / `--mpd`. `WORD` filters.
- `mpdbar-probe use NAME` checks that a playlist exists and has stations, then saves it in the
  config file. Duplicate Mopidy names are saved as the unambiguous URI.
- README: finding the playlist name, including `curl` + `jq` and `mpc` / `nc` recipes that keep
  the Cloudflare token out of the process list.

### Changed
- `mpdbar-probe init` writes an empty playlist; an empty playlist points to `mpdbar-probe playlists`.

## [0.2.0] - 2026-10-16

### Changed
- Settings move to one JSON file, `~/.config/mpd-bar/config.json` (or `$MPDBAR_CONFIG`,
  `$XDG_CONFIG_HOME/mpd-bar/config.json`), shared by the app and `mpdbar-probe`. The app reloads
  it when it changes. The file is written with mode 600 and reset to 600 on every read.
- The Settings panel shows the file path, whether it parses, and offers **Create config file**,
  **Open**, **Reveal**, **Reload** and **Test**. Errors name the exact key at fault.
- `mpdbar-probe` without arguments tests the server in the config file; `mpdbar-probe init`
  writes a template; `--config PATH` reads another file; `--help` prints the usage.

### Removed
- Keychain and UserDefaults storage. Settings from 0.1.x are not migrated: create the config
  file once (`mpdbar-probe init`). The README lists the commands that remove the leftovers.

## [0.1.2] - 2026-10-16

### Fixed
- Build failure with the macOS 27 SDK command line tools ("cannot assign to property: 'self' is
  immutable" in `SettingsView`). Settings fields and hover flags now live in `ObservableObject`
  classes instead of view `@State` mutated from methods.
- Swift 6 language mode: backend actions run on the main actor, removing a data-race diagnostic.

### Added
- CI job building with the newest installed Xcode on macOS 15 and macOS 26, with warnings as
  errors, in both Swift 5 and Swift 6 language modes.

## [0.1.1] - 2026-10-16

### Added
- GitHub release for every tag: universal app zip, command-line probe zip, `SHA256SUMS`,
  install and upgrade instructions. The Homebrew formula is updated automatically.
- Secret scanning: Gitleaks (full history and pre-commit hook) and TruffleHog in CI.
- CodeQL analysis of the Swift code and OpenSSF Scorecard.
- Dependabot for GitHub Actions; every Action is pinned to a commit SHA.
- `SECURITY.md`, `CONTRIBUTING.md`, issue and pull request templates.
- `scripts/check-version.sh` and `scripts/release-notes.sh`.

### Changed
- `scripts/bundle.sh` builds a universal (arm64 + x86_64) app with `UNIVERSAL=1` and also
  produces `build/mpdbar-probe`.

## [0.1.0] - 2026-10-16

### Added
- Menu bar app (SwiftUI `MenuBarExtra`): now playing, play / pause / stop, previous and next
  station, volume, one button per station of a server playlist.
- Mopidy backend over HTTP JSON-RPC, direct or behind Cloudflare Access (service token).
- MPD backend over TCP, with optional password.
- In-app settings with a **Test** button; secrets stored in the login Keychain.
- `mpdbar-probe` command-line check, read-only unless `--write`.
- Homebrew formula building from source, with a `brew services` launch agent.
- CI on macOS: build, MPD integration test, formula install from HEAD.

[Unreleased]: https://github.com/ts-sz/mpd-bar/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/ts-sz/mpd-bar/compare/v0.3.2...v0.4.0
[0.3.2]: https://github.com/ts-sz/mpd-bar/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/ts-sz/mpd-bar/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/ts-sz/mpd-bar/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ts-sz/mpd-bar/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/ts-sz/mpd-bar/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/ts-sz/mpd-bar/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ts-sz/mpd-bar/releases/tag/v0.1.0
