#!/bin/bash
# vpn-health-check.sh - Verify the full VPN tunnel chain for qBittorrent
#
# Checks:
#   1. Gluetun container running
#   2. Gluetun Docker health status is "healthy"
#   3. VPN exit IP matches VPS IP (from Vault)
#   4. Port 6881 reachable from VPS
#   5. WireGuard handshake on VPS is recent (< 3 min)
#
# Usage:
#   ./vpn-health-check.sh
#
# Requires: docker, vault, ssh access to VPS, jq
# Exit codes: 0 = all checks pass, 1 = one or more checks failed

set -eo pipefail

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; ((PASS++)); }
fail() { echo "  FAIL: $1"; ((FAIL++)); }

# Resolve VPS SSH connection from Ansible inventory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_FILE="$SCRIPT_DIR/../../hosts.ini"

if [[ -f "$HOSTS_FILE" ]]; then
    VPS_HOST=$(awk '/^\[vps\]/{getline; print $1}' "$HOSTS_FILE")
    VPS_USER=$(awk '/^\[vps\]/{getline; match($0, /ansible_user=([^ ]+)/, a); print a[1]}' "$HOSTS_FILE")
    VPS_PORT=$(awk '/^\[vps\]/{getline; match($0, /ansible_port=([^ ]+)/, a); print a[1]}' "$HOSTS_FILE")
    VPS_KEY=$(awk '/^\[vps\]/{getline; match($0, /ansible_ssh_private_key_file=([^ ]+)/, a); print a[1]}' "$HOSTS_FILE")
else
    echo "Warning: hosts.ini not found, SSH checks will be skipped" >&2
fi

VPS_PORT="${VPS_PORT:-22}"
VPS_KEY="${VPS_KEY:-$HOME/.ssh/vps}"
# Expand ~ in key path
VPS_KEY="${VPS_KEY/#\~/$HOME}"

# Get VPS IP from Vault
VPS_IP=$(vault kv get -format=json secret/wireguard | jq -r '.data.data.endpoint')

echo "VPN Health Check"
echo "================"
echo "VPS IP: $VPS_IP"
echo ""

# 1. Gluetun container running
echo "[1/5] Gluetun container running"
CONTAINER_STATE=$(docker inspect --format='{{.State.Running}}' gluetun 2>/dev/null || echo "not_found")
if [[ "$CONTAINER_STATE" == "true" ]]; then
    pass "gluetun container is running"
else
    fail "gluetun container is not running (state: $CONTAINER_STATE)"
fi

# 2. Gluetun healthy
echo "[2/5] Gluetun health status"
HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' gluetun 2>/dev/null || echo "unknown")
if [[ "$HEALTH_STATUS" == "healthy" ]]; then
    pass "gluetun health status is healthy"
else
    fail "gluetun health status is '$HEALTH_STATUS' (expected: healthy)"
fi

# 3. VPN exit IP matches VPS
echo "[3/5] VPN exit IP"
EXIT_IP=$(docker exec gluetun wget -qO- --timeout=10 https://ifconfig.me 2>/dev/null || echo "")
if [[ -z "$EXIT_IP" ]]; then
    fail "could not determine exit IP (tunnel may be down)"
elif [[ "$EXIT_IP" == "$VPS_IP" ]]; then
    pass "exit IP ($EXIT_IP) matches VPS IP"
else
    fail "exit IP ($EXIT_IP) does not match VPS IP ($VPS_IP)"
fi

# 4. Port 6881 reachable from VPS
echo "[4/5] Port 6881 reachable"
if [[ -n "$VPS_HOST" && -n "$VPS_USER" ]]; then
    PORT_CHECK=$(ssh -i "$VPS_KEY" -p "$VPS_PORT" -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
        "${VPS_USER}@${VPS_HOST}" "nc -z -w3 10.10.0.2 6881 && echo open || echo closed" 2>/dev/null || echo "ssh_failed")
    if [[ "$PORT_CHECK" == "open" ]]; then
        pass "port 6881 is reachable from VPS"
    elif [[ "$PORT_CHECK" == "ssh_failed" ]]; then
        fail "could not SSH to VPS to check port"
    else
        fail "port 6881 is not reachable from VPS"
    fi
else
    fail "VPS SSH details not available, skipping port check"
fi

# 5. WireGuard handshake freshness
echo "[5/5] WireGuard handshake freshness"
if [[ -n "$VPS_HOST" && -n "$VPS_USER" ]]; then
    HANDSHAKE_EPOCH=$(ssh -i "$VPS_KEY" -p "$VPS_PORT" -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
        "${VPS_USER}@${VPS_HOST}" "sudo wg show wg0 latest-handshakes | awk '{print \$2}'" 2>/dev/null || echo "")
    if [[ -z "$HANDSHAKE_EPOCH" || "$HANDSHAKE_EPOCH" == "0" ]]; then
        fail "no WireGuard handshake recorded"
    else
        NOW=$(date +%s)
        AGE=$(( NOW - HANDSHAKE_EPOCH ))
        if (( AGE < 180 )); then
            pass "last handshake was ${AGE}s ago (< 3 min)"
        else
            fail "last handshake was ${AGE}s ago (>= 3 min, tunnel may be stale)"
        fi
    fi
else
    fail "VPS SSH details not available, skipping handshake check"
fi

# Summary
echo ""
echo "Results: $PASS passed, $FAIL failed"

if (( FAIL > 0 )); then
    exit 1
fi
