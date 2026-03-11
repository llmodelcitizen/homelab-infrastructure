#!/bin/bash
# Wait for gluetun to establish the WireGuard tunnel before qBittorrent starts.
# libtorrent binds to each network interface at startup. If tun0 doesn't exist
# yet, it never binds to it and the torrent port is unreachable through the VPN.

TIMEOUT=60

echo "Waiting for tun0 interface..."
for i in $(seq 1 "$TIMEOUT"); do
    if ip link show tun0 &>/dev/null; then
        echo "tun0 is up after ${i}s."
        exit 0
    fi
    sleep 1
done

echo "ERROR: tun0 not found after ${TIMEOUT}s"
exit 1
