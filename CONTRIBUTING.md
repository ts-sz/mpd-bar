# Contributing

Thanks for helping. Bug reports, fixes and small features are welcome.

## Before you start

- Open an issue for anything larger than a small fix, so the approach can be agreed first.
- Security problems go through a private advisory, not an issue: see `SECURITY.md`.
- Coding agents: `AGENTS.md` is the full technical manual (architecture, build, release).

## Development setup

Requirements: macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/ts-sz/mpd-bar && cd mpd-bar
scripts/bundle.sh --install       # build, copy to ~/Applications, launch
```

Install the pre-commit hook, which blocks commits that contain secrets:

```bash
brew install pre-commit gitleaks
pre-commit install
```

## Testing

Run the probe against a server you control (a local MPD is easiest: `brew install mpd`).
`--write` plays, sets the volume to 37 and stops, so never point it at a shared room.

```bash
build/mpdbar-probe --mpd 127.0.0.1:6600 --playlist NAME
build/mpdbar-probe --mpd 127.0.0.1:6600 --playlist NAME --write
MPDBAR_CONFIG=/tmp/t.json build/mpdbar-probe init     # config file path, without touching yours
build/mpdbar-probe --mpd 127.0.0.1:6600 playlists
```

CI runs the same checks against an MPD started in the runner, plus CodeQL and the secret
scanners. A pull request is ready when CI is green.

## Pull requests

- One topic per pull request, with a short description of what changed and why.
- Commit messages in English, imperative mood (`Add MPD password support`), body explaining why.
- Add a line under `## [Unreleased]` in `CHANGELOG.md` for any user-visible change.
- New behaviour lands in the `PlayerBackend` protocol and in both backends, or is shown only
  where the backend supports it.
- No new dependencies: the package uses Apple frameworks only.

## Releases

Maintainers only. The procedure is in `AGENTS.md`, section Release.
