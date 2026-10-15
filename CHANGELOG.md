# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/ts-sz/mpd-bar/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/ts-sz/mpd-bar/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ts-sz/mpd-bar/releases/tag/v0.1.0
