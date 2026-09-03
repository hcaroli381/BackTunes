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
#   - catch: omnisette-server replies with Content-Type: text/plain and
#     AltServer's strict HTTP client only parses application/json, so a tiny
#     header-fixing proxy sits in front (6969 = proxy, 7969 = omnisette).

# Clean up any previous-layout instances (omnisette on 6969).
pkill -f 'omnisette-server --http-port 69[6]9' 2> /dev/null || true

if ! pgrep -f 'omnisette-serve[r]' > /dev/null 2>&1; then
    echo "🧇 Starting local anisette server…"
    (cd Tools/anisette && setsid ./omnisette-server --http-port 7969 > /tmp/omnisette-server.log 2>&1 < /dev/null &)
    sleep 3
fi
if ! pgrep -f 'fix-headers-proxy[.]py' > /dev/null 2>&1; then
    echo "🔧 Starting anisette header proxy…"
    (setsid python3 Tools/anisette/fix-headers-proxy.py > /tmp/fix-headers-proxy.py.log 2>&1 < /dev/null &)
    sleep 1
fi

for i in 1 2 3 4 5; do
    if curl -s -m 2 http://127.0.0.1:6969 > /dev/null 2>&1; then break; fi
    sleep 1
done
if ! curl -s -m 2 http://127.0.0.1:6969 > /dev/null 2>&1; then
    echo "❌ Local anisette server failed to start — see /tmp/*.log"
    exit 1
fi
echo "🧇 Local anisette server ready on 127.0.0.1:6969"
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
