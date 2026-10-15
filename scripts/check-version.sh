#!/bin/bash
# Fail unless the given tag (vX.Y.Z) matches every version string in the repo.
#   scripts/check-version.sh v0.1.1
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?usage: scripts/check-version.sh vX.Y.Z}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Tag must look like vX.Y.Z, got $TAG" >&2; exit 1; }
V="${TAG#v}"

plist=$(/usr/bin/plutil -extract CFBundleShortVersionString raw Resources/Info.plist 2>/dev/null \
  || sed -n '/CFBundleShortVersionString/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' Resources/Info.plist)
swift=$(sed -n 's/.*static let string = "\(.*\)".*/\1/p' Sources/MPDBarCore/Models.swift)
changelog=$(grep -c "^## \[$V\]" CHANGELOG.md || true)

ok=1
[[ "$plist" == "$V" ]] || { echo "Resources/Info.plist says $plist, tag says $V" >&2; ok=0; }
[[ "$swift" == "$V" ]] || { echo "Sources/MPDBarCore/Models.swift says $swift, tag says $V" >&2; ok=0; }
[[ "$changelog" == "1" ]] || { echo "CHANGELOG.md has no '## [$V]' section" >&2; ok=0; }
[[ "$ok" == "1" ]] && echo "Version $V is consistent."
[[ "$ok" == "1" ]]
