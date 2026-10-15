# Security policy

## Supported versions

Only the latest release receives fixes. Upgrade with `brew upgrade mpd-bar`.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub:
**Security** tab of this repository, then **Report a vulnerability**
(<https://github.com/ts-sz/mpd-bar/security/advisories/new>).

Do not open a public issue for a vulnerability. Include the version (`mpdbar-probe` prints it
in its usage line), your macOS version, and the steps to reproduce.

You will get an acknowledgement within 7 days. A fix is released as a new version, with the
advisory published once users can upgrade.

## How the app handles secrets

- The Cloudflare Access client ID and secret and the MPD password are stored in the login
  Keychain (service `mpd-bar`). They are never written to disk elsewhere, logged, or sent to
  any host other than the server you configure.
- Settings that are not secret (server URL, host, port, playlist) live in the app's
  UserDefaults (`io.github.ts-sz.mpd-bar`).
- The MPD protocol is plain text TCP: the password and commands travel unencrypted. Use MPD
  on a trusted network or through a VPN. Mopidy over `https://` is encrypted.
- The app makes no network connection other than to the configured server: no telemetry,
  no update check.

## How the repository is protected

- Gitleaks scans the full Git history on every push and pull request, and a pre-commit hook
  scans staged changes (see `CONTRIBUTING.md`).
- TruffleHog scans independently for live credentials.
- CodeQL analyses the Swift code; OpenSSF Scorecard reports on supply-chain practices.
- Every GitHub Action is pinned to a commit SHA and kept current by Dependabot.
- Release archives are published with a `SHA256SUMS` file.
