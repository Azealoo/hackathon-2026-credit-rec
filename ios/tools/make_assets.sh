#!/bin/bash
# Rebuilds Paywise's visual assets: card art and the accent color (docs/design.md §2, §6–§7); the app icon, the in-app logo
# `mark` and the Live Activity glyph (the island mark), all logo option 08 "Monoline" (brand/08-monoline); and silent.caf.
# Run from anywhere:
#
#   ios/tools/make_assets.sh                      # keeps the standard app icon already in AppIcon.appiconset
#   ios/tools/make_assets.sh path/to/icon.png     # replaces it with this opaque 1024 × 1024 PNG first
#
# Dark and tinted icons are always redrawn from brand/08-monoline/app-icon.svg (see make_assets.swift).
# Then commit the changed files under ios/Shared/Assets.xcassets, ios/Paywise/Assets.xcassets and ios/Shared/Sounds.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/paywise-assets.XXXXXX")"
trap 'rm -rf "$work"' EXIT

icon=()
if [ $# -ge 1 ]; then
  icon=("$(cd "$(dirname "$1")" && pwd)/$(basename "$1")")
fi

xcrun swift "$here/make_assets.swift" "$root" "$work/silence.wav" ${icon[@]+"${icon[@]}"}

# silent.caf (design.md §7): 10 ms of true silence, linear PCM, mono, 44.1 kHz. Bundled in the app and the widget.
mkdir -p "$root/ios/Shared/Sounds"
afconvert -f caff -d LEI16@44100 -c 1 "$work/silence.wav" "$root/ios/Shared/Sounds/silent.caf"
echo "silent.caf: $(afinfo "$root/ios/Shared/Sounds/silent.caf" | grep -E 'estimated duration' | sed 's/^ *//')"
