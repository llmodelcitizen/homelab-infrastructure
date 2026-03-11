#!/bin/bash
# Test alert pipeline by temporarily lowering thresholds
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RULES_FILE="prometheus/alert-rules.yml"

echo "Backing up rules..."
cp "$RULES_FILE" "$RULES_FILE.bak"

echo "Lowering thresholds (> 1) and wait time (10s)..."
# Use temp file to preserve inode (bind mount issue with sed -i)
sed 's/> 90/> 1/g; s/> 95/> 1/g; s/for: 5m/for: 10s/g' "$RULES_FILE.bak" > "$RULES_FILE"

echo "Clearing alertmanager notification log..."
./monitoringctl stop alertmanager
sudo rm -f /opt/grafana/alertmanager/nflog

echo "Restarting prometheus and alertmanager..."
./monitoringctl restart prometheus
./monitoringctl start alertmanager

echo "Waiting 45s for alerts to fire and send..."
sleep 45

echo "Alert status:"
docker exec prometheus wget -qO- 'http://localhost:9090/api/v1/alerts' | jq -r '.data.alerts[] | "\(.labels.alertname) [\(.labels.mountpoint)]: \(.state)"'

echo ""
echo "Notification log:"
docker logs alertmanager 2>&1 | grep -i "notify" | tail -5

echo ""
read -p "Press Enter to restore original rules..."

echo "Restoring rules..."
mv "$RULES_FILE.bak" "$RULES_FILE"
./monitoringctl restart prometheus

echo "Done. Check your email for test alerts."
