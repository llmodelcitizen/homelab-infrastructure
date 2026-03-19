#!/bin/bash
# Wait for gluetun's VPN tunnel to be fully healthy before qBittorrent starts.
# libtorrent binds to each network interface at startup. If tun0 doesn't exist
# yet (or gets recreated after a failed healthcheck), qBittorrent never binds to
# it and the torrent port is unreachable through the VPN.
#
# Checking tun0 alone is insufficient — gluetun may tear down and recreate it if
# the initial healthcheck fails (e.g. DNS timeout during startup). We must wait
# for the healthcheck to pass so tun0 is in its final, stable state.

TIMEOUT=90

echo "Waiting for tun0 interface..."
for i in $(seq 1 "$TIMEOUT"); do
    if ip link show tun0 &>/dev/null; then
        echo "tun0 is up after ${i}s."
        break
    fi
    sleep 1
    if [ "$i" -eq "$TIMEOUT" ]; then
        echo "ERROR: tun0 not found after ${TIMEOUT}s"
        exit 1
    fi
done

echo "Waiting for gluetun healthcheck to pass..."
for i in $(seq 1 "$TIMEOUT"); do
    if wget -qO/dev/null --timeout=3 http://127.0.0.1:9999 2>/dev/null; then
        echo "Healthcheck passed after ${i}s — VPN is stable."
        exit 0
    fi
    sleep 1
done

echo "ERROR: gluetun healthcheck did not pass after ${TIMEOUT}s"
exit 1
