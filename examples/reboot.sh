#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PYTHON="$HOME/.venvs/adb-discovery/bin/python"
TARGET=""

for COMMAND in adb timeout; do
    if ! command -v "$COMMAND" >/dev/null 2>&1; then
        echo "Error: required command not found: $COMMAND" >&2
        exit 1
    fi
done

if [[ ! -x "$PYTHON" ]]; then
    echo "Error: discovery environment not found: $PYTHON" >&2
    exit 1
fi

if ! "$PYTHON" -c 'import zeroconf'; then
    echo "Error: zeroconf is not available in the discovery environment." >&2
    exit 1
fi

discover_ports() {
    "$PYTHON" - <<'PY'
import threading
import time

from zeroconf import IPVersion, ServiceBrowser, ServiceListener, Zeroconf

SERVICE_TYPE = "_adb-tls-connect._tcp.local."


class Listener(ServiceListener):
    def __init__(self):
        self.names = set()
        self.lock = threading.Lock()

    def add_service(self, resolver, service_type, name):
        with self.lock:
            self.names.add(name)

    def update_service(self, resolver, service_type, name):
        self.add_service(resolver, service_type, name)

    def remove_service(self, resolver, service_type, name):
        with self.lock:
            self.names.discard(name)


listener = Listener()

with Zeroconf(ip_version=IPVersion.V4Only) as resolver:
    browser = ServiceBrowser(resolver, SERVICE_TYPE, listener)
    try:
        time.sleep(8)

        with listener.lock:
            names = sorted(listener.names)

        ports = set()
        for name in names:
            info = resolver.get_service_info(
                SERVICE_TYPE, name, timeout=3000
            )
            if info is not None and 1 <= info.port <= 65535:
                ports.add(info.port)

        for port in sorted(ports):
            print(port)
    finally:
        browser.cancel()
PY
}

connect_local_device() {
    local PORTS PORT STATE
    TARGET=""

    if ! PORTS="$(discover_ports)"; then
        echo "Error: service discovery failed." >&2
        return 1
    fi

    while IFS= read -r PORT; do
        [[ "$PORT" =~ ^[0-9]+$ ]] || continue
        TARGET="127.0.0.1:$PORT"

        if ! timeout 5 adb connect "$TARGET" >/dev/null 2>&1; then
            continue
        fi

        STATE="$(
            timeout 5 adb -s "$TARGET" get-state 2>/dev/null || true
        )"

        if [[ "$STATE" == "device" ]]; then
            return 0
        fi
    done <<< "$PORTS"

    TARGET=""
    return 1
}

if ! command -v wireless-debugging >/dev/null 2>&1; then
    echo "Error: required command not found: wireless-debugging" >&2
    exit 1
fi

adb start-server >/dev/null

echo "Requesting Wireless debugging activation..."

# Verify ADB availability even if the activity launcher reports an error.
if ! wireless-debugging on; then
    echo "Warning: the activation command reported an error." >&2
    echo "Continuing with discovery to verify ADB availability." >&2
fi

echo "Discovering local Wireless debugging..."

if ! connect_local_device; then
    echo "Could not connect. Pairing may be required."
    echo "Make sure Wireless debugging is enabled."
    echo

    read -r -p "Start interactive pairing? [y/N] " ANSWER

    case "$ANSWER" in
        y|Y|yes|YES) ;;
        *)
            echo "Cancelled. Device was not rebooted."
            exit 1
            ;;
    esac

    echo
    echo "On this phone, open:"
    echo "Settings > Developer options > Wireless debugging"
    echo "> Pair device with pairing code"
    echo "Keep the pairing dialog open."
    echo

    read -r -p "Pairing port: " PAIR_PORT

    if [[ ! "$PAIR_PORT" =~ ^[0-9]{1,5}$ ]]; then
        echo "Error: invalid pairing port." >&2
        exit 1
    fi

    if (( 10#$PAIR_PORT < 1 || 10#$PAIR_PORT > 65535 )); then
        echo "Error: port must be between 1 and 65535." >&2
        exit 1
    fi

    echo "Enter the pairing code when adb asks for it."

    if ! adb pair "127.0.0.1:$PAIR_PORT"; then
        echo "Error: pairing failed. Device was not rebooted." >&2
        exit 1
    fi

    echo "Discovering the connection port..."

    if ! connect_local_device; then
        echo "Error: could not connect after pairing." >&2
        echo "Device was not rebooted." >&2
        exit 1
    fi
fi

echo "Connected to $TARGET."
echo "Rebooting device..."
adb -s "$TARGET" reboot
