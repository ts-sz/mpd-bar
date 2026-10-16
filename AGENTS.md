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
scripts/bundle.sh              build MPDBar.app + mpdbar-probe; --install; UNIVERSAL=1
scripts/check-version.sh       tag vs Info.plist vs Models.swift vs CHANGELOG
scripts/release-notes.sh       release page body (changes, install, upgrade, checksums)
Formula/mpd-bar.rb             Homebrew formula (this repo doubles as the tap)
.github/workflows/ci.yml       build, MPD integration test, release scripts, formula from HEAD
.github/workflows/secrets.yml  Gitleaks full history (pinned CLI, checksum) + TruffleHog
.github/workflows/codeql.yml   CodeQL Swift, security-and-quality
.github/workflows/scorecard.yml OpenSSF Scorecard (published, SARIF to code scanning)
.github/workflows/release.yml  tag -> assets, release page, formula bump, stable brew install
.gitleaks.toml                 default rules + Cloudflare Access client ID rule
.pre-commit-config.yaml        gitleaks on staged changes
```

## Build and test

```bash
swift build -c release                  # all targets
scripts/bundle.sh                       # build/MPDBar.app and build/mpdbar-probe
scripts/bundle.sh --install             # copy to ~/Applications and launch
build/mpdbar-probe --mpd 127.0.0.1:6600 --playlist NAME
```

CI (`macos-14`) builds everything, starts a local MPD with a null audio output and a
two-station playlist, runs the probe read-only, then with `--write`, checks the
unknown-playlist error, dry-runs the release scripts, and installs the formula from HEAD.
A second job builds with the newest installed Xcode on macOS 15 and 26, warnings as errors, in Swift 5
and Swift 6 language modes: Macs often run a newer toolchain than the main job. Never mutate view
`@State` from methods; keep mutable view state in `ObservableObject` classes (the macOS 27 SDK rejects it).
CodeQL and both secret scanners run on every push and pull request.
A change is done when every workflow is green.

Polling: the app refreshes every 4 s while the panel is open and every 30 s otherwise.
Mopidy refresh is one HTTP request (JSON-RPC batch); MPD refresh is one TCP session
(`status` + `currentsong` in a command list).

## Security gates

- Never commit a secret, a real server address or a Cloudflare Access client ID. Examples use
  `music.local`, `music.example.com`, `...`.
- `pre-commit install` once per clone: gitleaks blocks staged secrets. CI rescans the full
  history, so a secret that slips through fails the build and must be rotated, not just removed.
- Every Action is pinned to a full commit SHA with the tag in a comment. Resolve a new SHA with
  `git ls-remote https://github.com/<owner>/<action>.git refs/tags/<tag>`, never from memory.
  Dependabot proposes updates weekly.
- Workflows default to `contents: read`; only release jobs get `contents: write`.

## Release

Releases are cut by pushing a tag; `.github/workflows/release.yml` does the rest.

1. Move the `## [Unreleased]` entries of `CHANGELOG.md` under `## [X.Y.Z] - YYYY-MM-DD` and
   update the compare links at the bottom.
2. Set `X.Y.Z` in `Version.string` (`Sources/MPDBarCore/Models.swift`) and in
   `CFBundleShortVersionString` (`Resources/Info.plist`). Check with
   `scripts/check-version.sh vX.Y.Z`.
3. Commit (`Release vX.Y.Z`), push to `main`, wait for every workflow to be green.
4. `git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`.
5. The release workflow then:
   - fails early unless the tag matches Info.plist, Models.swift and a CHANGELOG section;
   - builds universal binaries, checks both architectures, the ad-hoc signature and the probe;
   - publishes the GitHub release: `MPDBar-X.Y.Z-macos-universal.zip`,
     `mpdbar-probe-X.Y.Z-macos-universal.zip`, `SHA256SUMS`, notes from
     `scripts/release-notes.sh` (changes, install, upgrade, manual download, checksums);
   - points `Formula/mpd-bar.rb` at the tag tarball with its sha256 and pushes that to `main`;
   - installs the stable formula on a clean runner and runs `brew test`.
6. Check the release page, then on a Mac: `brew update && brew upgrade mpd-bar`.

A failed release run is safe to re-run: the publish step updates an existing release, and the
formula step is a no-op when the formula is already current.

## Conventions

- Swift 5 language mode, everything UI-facing and every backend is `@MainActor`.
  Network callbacks bridge to async with `withCheckedThrowingContinuation` and `OnceFlag`.
- Errors surface as `PlayerError` with a short English sentence the panel can show as is.
- Commit messages in English, imperative mood, body explaining why.
- `CLAUDE.md` and `.github/copilot-instructions.md` point here; this file is the single source.
