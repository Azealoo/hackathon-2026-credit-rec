#!/bin/bash
# Rebuilds Paywise's visual assets from docs/design.md §5–§7: card art, the glyph, the accent color, the app icon
# and silent.caf. Run from anywhere:  ios/tools/make_assets.sh
# Then commit the changed files under ios/Shared/Assets.xcassets, ios/Paywise/Assets.xcassets and ios/Shared/Sounds.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/paywise-assets.XXXXXX")"
trap 'rm -rf "$work"' EXIT

xcrun swift "$here/make_assets.swift" "$root" "$work/silence.wav"

# silent.caf (design.md §7): 10 ms of true silence, linear PCM, mono, 44.1 kHz. Bundled in the app and the widget.
mkdir -p "$root/ios/Shared/Sounds"
afconvert -f caff -d LEI16@44100 -c 1 "$work/silence.wav" "$root/ios/Shared/Sounds/silent.caf"
echo "silent.caf: $(afinfo "$root/ios/Shared/Sounds/silent.caf" | grep -E 'estimated duration' | sed 's/^ *//')"
