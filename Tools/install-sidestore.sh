#!/usr/bin/env bash
# Installs SideStore + BackTunes onto a plugged-in iPhone using AltServer-Linux.
# Run from the project root:  ./Tools/install-sidestore.sh
#
# The Apple ID password is read with hidden input and never stored or logged.
# Tip: if your Apple ID has two-factor auth, use an app-specific password
# from https://appleid.apple.com -> Sign-In and Security -> App-Specific Passwords.
set -e
cd "$(dirname "$0")/.."

UDID=$(idevice_id -l | head -1)
if [ -z "$UDID" ]; then
    echo "❌ No iPhone detected. Plug it in, unlock it, and accept the Trust dialog."
    exit 1
fi
echo "📱 Device found: $UDID"

read -rsp "🔑 Apple ID (email): " APPLE_ID; echo
read -rsp "🔑 Apple ID password (hidden input): " APPLE_PW; echo
echo

echo "📦 [1/2] Installing SideStore…"
Tools/altserver/AltServer -u "$UDID" -a "$APPLE_ID" -p "$APPLE_PW" dist/SideStore.ipa

echo
echo "📦 [2/2] Installing BackTunes…"
Tools/altserver/AltServer -u "$UDID" -a "$APPLE_ID" -p "$APPLE_PW" dist/BackTunes.ipa

echo
echo "✅ Done! On the iPhone:"
echo "   1. Settings → General → VPN & Device Management → trust your Apple ID"
echo "   2. (iOS 16+) Settings → Privacy & Security → Developer Mode → ON"
echo "   3. Open SideStore, approve its VPN profile, then open BackTunes 🎉"
