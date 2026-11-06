#!/usr/bin/env bash
# swift-collections 1.6.0's versioned Swift 6.0 manifest omits its traits.
# SwiftPM accepts the requested trait, but Xcode rejects it during resolution.
# Use the package's Swift 6.2 manifest with our required Swift 6.4 toolchain.
# Only the ignored, pinned checkout is adjusted; dependency sources are unchanged.
set -euo pipefail
cd "$(dirname "$0")/.."
checkout=.build/checkouts/swift-collections
expected=a0cb0954ecb21e4e31b0070e6ed5674e8556685a
if [[ "$(git -C "$checkout" rev-parse HEAD)" != "$expected" ]]; then
    echo 'Review the swift-collections manifest workaround after changing its pin' >&2
    exit 1
fi
manifest="$checkout/Package@swift-6.0.swift"
if [[ -f "$manifest" ]]; then
    mv "$manifest" "$manifest.disabled"
fi
