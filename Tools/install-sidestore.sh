#!/usr/bin/env bash
# Installs SideStore + BackTunes onto a plugged-in iPhone using AltServer-Linux.
# Run from the project root:  ./Tools/install-sidestore.sh
#
# The Apple ID password is read with hidden input and never stored or logged.
# Tip: if your Apple ID has two-factor auth, use an app-specific password
# from https://appleid.apple.com -> Sign-In and Security -> App-Specific Passwords.
set -e
cd "$(dirname "$0")/.."

# Anisette strategy:
#   - AltServer's default server (armconverter.com) is dead (502)
#   - public servers like ani.sidestore.io share one Apple identity, which
#     Apple throttles -> "auth response status code: 503"
#   - so we run a LOCAL anisette server (SideStore's omnisette-server) that
#     generates our own unique machine data. It needs the Apple Music ADI
#     libs, already extracted under Tools/anisette/lib/.
if ! curl -s -m 2 http://127.0.0.1:6969 > /dev/null 2>&1; then
    echo "🧇 Starting local anisette server…"
    (setsid Tools/anisette/omnisette-server --http-port 6969 > /tmp/anisette.log 2>&1 < /dev/null &)
    sleep 3
fi
export ALTSERVER_ANISETTE_SERVER="http://127.0.0.1:6969"

UDID=$(idevice_id -l | head -1)
if [ -z "$UDID" ]; then
    echo "❌ No iPhone detected. Plug it in, unlock it, and accept the Trust dialog."
    exit 1
fi
echo "📱 Device found: $UDID"

read -rsp "🔑 Apple ID (email): " APPLE_ID; echo
read -rsp "🔑 Apple ID password (hidden input): " APPLE_PW; echo
echo

install_ipa() {
    local ipa="$1"
    echo "📦 Installing $ipa…"
    if ! Tools/altserver/AltServer -d -u "$UDID" -a "$APPLE_ID" -p "$APPLE_PW" "dist/$ipa"; then
        echo "❌ Failed to install $ipa — see output above."
        exit 1
    fi
    echo "✅ $ipa installed."
    echo
}

install_ipa SideStore.ipa
install_ipa BackTunes.ipa

echo "🎉 All done! On the iPhone:"
echo "   1. Settings → General → VPN & Device Management → trust your Apple ID"
echo "   2. (iOS 16+) Settings → Privacy & Security → Developer Mode → ON"
echo "   3. Open SideStore, approve its VPN profile, then open BackTunes"
