#!/usr/bin/env bash
# Build HarvestInn for a connected iPhone and install it (free Apple ID is enough; app expires in 7 days).
#
#   tools/ios_install.sh <TEAM_ID> [BUNDLE_ID]
#
# TEAM_ID: Xcode → Settings → Accounts → your team (or the OU= field of your "Apple Development" cert).
# Needs: Xcode, Godot 4.7.2 + export templates, iPhone plugged in with Developer Mode on.
set -euo pipefail
cd "$(dirname "$0")/.."
TEAM="${1:?usage: tools/ios_install.sh <TEAM_ID> [BUNDLE_ID]}"
BUNDLE="${2:-com.harvestinn.game}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
OUT=build/ios

# The team id is personal: inject it into a temporary copy of the presets, never into git.
cp export_presets.cfg /tmp/harvestinn_presets.bak
trap 'cp /tmp/harvestinn_presets.bak export_presets.cfg' EXIT
sed -i '' -e "s/^application\/app_store_team_id=.*/application\/app_store_team_id=\"$TEAM\"/" \
          -e "s/^application\/bundle_identifier=.*/application\/bundle_identifier=\"$BUNDLE\"/" export_presets.cfg

rm -rf "$OUT" && mkdir -p "$OUT"
godot --headless --path . --export-debug "iOS" "$OUT/HarvestInn.xcodeproj"

DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/connected/ && /physical/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) print $i}' | head -1)
[ -n "$DEVICE" ] || { echo "No connected iPhone found (plug it in, unlock it, trust this Mac)."; exit 1; }

xcodebuild -project "$OUT/HarvestInn.xcodeproj" -scheme HarvestInn -configuration Debug \
  -destination "id=$DEVICE" -derivedDataPath "$OUT/derived" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" CODE_SIGN_STYLE=Automatic build | tail -5

APP=$(find "$OUT/derived/Build/Products" -name "*.app" -maxdepth 2 | head -1)
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "Installed. If iOS says 'Untrusted Developer': Settings → General → VPN & Device Management → trust your Apple ID."
