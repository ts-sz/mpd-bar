#!/bin/bash
# Write the GitHub release notes for a tag to stdout.
#   scripts/release-notes.sh v0.1.1 [SHA256SUMS]
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?usage: scripts/release-notes.sh vX.Y.Z [SHA256SUMS]}"
V="${TAG#v}"
SUMS="${2:-}"
REPO="${GITHUB_REPOSITORY:-ts-sz/mpd-bar}"

changes=$(awk -v v="$V" '
  $0 ~ "^## \\[" v "\\]" { on = 1; next }
  on && /^## \[/ { exit }
  on { print }
' CHANGELOG.md | sed -e '/./,$!d')

cat <<EOF
Menu bar remote for MPD and Mopidy web radio playlists. macOS 13 Ventura or later, Apple silicon and Intel.

## What's new

${changes}

## Install

Homebrew builds the app on your Mac from source (needs the Xcode Command Line Tools: \`xcode-select --install\`).

\`\`\`bash
brew tap ts-sz/mpd-bar https://github.com/${REPO}
brew install ts-sz/mpd-bar/mpd-bar
brew services start mpd-bar      # start now and at every login
\`\`\`

Click the radio icon in the menu bar, fill in **Settings**, press **Test**, then **Save**.

## Upgrade

\`\`\`bash
brew update
brew upgrade mpd-bar
brew services restart mpd-bar
\`\`\`

Settings and Keychain secrets are kept across upgrades.

## Manual download (without Homebrew)

\`MPDBar-${V}-macos-universal.zip\` holds the app, ad-hoc signed and not notarized. macOS blocks
apps downloaded from a browser until the quarantine flag is removed:

\`\`\`bash
unzip MPDBar-${V}-macos-universal.zip -d ~/Applications
xattr -dr com.apple.quarantine ~/Applications/MPDBar.app
open ~/Applications/MPDBar.app
\`\`\`

\`mpdbar-probe-${V}-macos-universal.zip\` holds the command-line probe (\`mpdbar-probe --help\`).
The Homebrew install is the recommended path: it needs no quarantine step and updates with \`brew upgrade\`.

## Verify the download

\`\`\`bash
shasum -a 256 -c SHA256SUMS
\`\`\`
EOF

if [[ -n "$SUMS" && -f "$SUMS" ]]; then
  printf '\n```\n'
  cat "$SUMS"
  printf '```\n'
fi

cat <<EOF

Full changelog: [CHANGELOG.md](https://github.com/${REPO}/blob/${TAG}/CHANGELOG.md)
EOF
