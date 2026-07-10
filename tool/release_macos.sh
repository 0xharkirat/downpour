#!/usr/bin/env bash
#
# Builds one universal (arm64 + x86_64) macOS release, ad-hoc signs it, and
# packages it as a drag-to-Applications .dmg:
#
#   dist/Downpour.dmg
#
# The DMG uses Finder's native appearance-adaptive window (no custom
# background) so icon labels stay readable in Dark and Light Mode. Built
# headlessly via dmgbuild - works over SSH and in CI.
#
# Requires: dmgbuild (pip install dmgbuild). Usage: tool/release_macos.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> flutter build macos --release (universal)"
flutter build macos --release

APP="build/macos/Build/Products/Release/Downpour.app"
echo "    archs: $(lipo -archs "$APP/Contents/MacOS/Downpour")"

echo "==> ad-hoc sign"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

echo "==> dist/Downpour.dmg"
mkdir -p dist
rm -f dist/Downpour.dmg
DMGBUILD="$(python3 -c 'import sys,os;print(os.path.join(sys.prefix,"bin","dmgbuild"))')"
"$DMGBUILD" -s tool/dmg_settings.py \
  -D app="$APP" \
  -D icon="$APP/Contents/Resources/AppIcon.icns" \
  "Downpour" dist/Downpour.dmg >/dev/null
echo "    $(du -h dist/Downpour.dmg | cut -f1)"
shasum -a 256 dist/Downpour.dmg
echo "==> done"
