#!/bin/bash
# Build + deploy TomatoBar to /Applications, preserving entitlements.
# Use this whenever the Personal Team provisioning profile expires (~7 days)
# or after any code change.

set -euo pipefail
cd "$(dirname "$0")"

echo "→ Building..."
xcodebuild -project TomatoBar.xcodeproj -scheme TomatoBar \
    -configuration Debug build > /tmp/tomatobar-build.log 2>&1 || {
    echo "✗ Build failed. See /tmp/tomatobar-build.log"
    tail -30 /tmp/tomatobar-build.log
    exit 1
}

BUILT=$(find ~/Library/Developer/Xcode/DerivedData/TomatoBar-* \
    -path "*/Build/Products/Debug/TomatoBar.app" -type d 2>/dev/null | head -1)
[ -d "$BUILT" ] || { echo "✗ Built .app not found"; exit 1; }

echo "→ Killing running TomatoBar..."
killall TomatoBar 2>/dev/null || true
sleep 1

echo "→ Deploying to /Applications..."
rm -rf /Applications/TomatoBar.app
cp -R "$BUILT" /Applications/

echo "→ Re-signing ad-hoc with entitlements preserved..."
codesign --force --deep --sign - \
    --entitlements TomatoBar/TomatoBar.entitlements \
    /Applications/TomatoBar.app

echo "→ Launching..."
open /Applications/TomatoBar.app

echo "✓ Done — $(date '+%H:%M:%S')"
