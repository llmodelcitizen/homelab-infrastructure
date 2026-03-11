# Observability Stack

### 1. Create directories

```bash
sudo mkdir -p /opt/grafana/{data,prometheus,alertmanager,loki,cloudtrail,diun}

sudo chown -R 472:472 /opt/grafana/data
sudo chown -R 65534:65534 /opt/grafana/prometheus
sudo chown -R 10001:10001 /opt/grafana/loki
```

### 2. Start services

```bash
./monitoringctl up -d      # Start stack
./monitoringctl logs -f    # View logs
./monitoringctl down       # Stop stack
```

## Components

| Component | Purpose | Port |
|-----------|---------|------|
| Grafana | Dashboards and visualization | 3000 |
| Prometheus | Metrics collection and storage | 9090 |
| Alertmanager | Alert routing and notifications | 9093 |
| Node Exporter | Host metrics | 9100 |
| cAdvisor | Container metrics | 8080 |
| Loki | Log aggregation | 3100 |
| Promtail | Log collection | 9080 |
| CloudTrail sync | S3 → NDJSON → Loki (WHOIS-enriched) | - |
| Diun | Docker image update notifications | - |

## UI Access

All dashboards protected by Authelia 2FA:

| Service | URL | Purpose |
|---------|-----|---------|
| Grafana | https://grafana.example.com | Dashboards, visualization, log exploration |
| Prometheus | https://prometheus.example.com | Metrics queries, targets, alert rules |
| Alertmanager | https://alertmanager.example.com | Alert status, silences, routing |
| cAdvisor | https://cadvisor.example.com | Container resource usage |

Grafana default admin password: `admin` (change after first login)

## Data Retention

| Component | Retention | Location |
|-----------|-----------|----------|
| Prometheus | 120 days / 20GB | `/opt/grafana/prometheus` |
| Loki | 30 days | `/opt/grafana/loki` |

## Pre-configured Dashboards

Some are custom and others are public and tailored for this environment.

- **Node Exporter Full** - Host system metrics (CPU, memory, disk, network)
- **Docker cAdvisor** - Container resource usage
- **Loki Logs** - Log exploration and search
- **Frigate Monitoring** - NVR metrics (camera FPS, detection, storage)
- **Traefik** - Reverse proxy metrics (requests, response times, errors)
- **CloudTrail** - AWS API activity (IAM users, source IPs, WHOIS org)
- **Docker Image Updates** - Diun update timeline, pending updates, check errors

## Updating Provisioned Dashboards

Dashboards are provisioned from JSON files in `grafana/provisioning/dashboards/json/`. The provisioner auto-reloads every 30 seconds.

### Editing a Dashboard

1. Edit the dashboard directly in Grafana UI
2. Click Settings → JSON Model tab → Copy to clipboard → Exit edit
3. Paste into the `.json` file, ensure `"id": null`
4. Wait 30 seconds for auto-reload

**Warning:** Don't use "Save As" to create a copy, then export the copy. This generates a new UID that won't match the provisioned file. Always edit and export the original dashboard.

### Resetting a Stuck Dashboard

If provisioning fails with "dashboard with same uid already exists", temporarily remove the file to un-provision, then restore it:

```bash
mv grafana/provisioning/dashboards/json/DASHBOARD.json /tmp/
sleep 35
mv /tmp/DASHBOARD.json grafana/provisioning/dashboards/json/
```

## Alerting

Alerts are sent via AWS SES to the recipient configured in `vars.yml`. At startup, `monitoringctl` renders config templates with Vault secrets and writes them to `/opt/grafana/` (`alertmanager/alertmanager.yml` and `diun/diun.yml`), keeping secrets out of the repo tree.

### Alert Rules

Alert rules are defined in `prometheus/alert-rules.yml` (gitignored). Copy the example to get started:

```bash
cp prometheus/alert-rules.yml.example prometheus/alert-rules.yml
```

The example includes:

- **DiskSpaceWarning** - Fires when `/` exceeds 90% capacity
- **DiskSpaceCritical** - Fires when `/` exceeds 95% capacity
- **HighCpuUsage** - Fires when CPU usage exceeds 90% for 5 minutes

### Managing Rules

**Recreate Prometheus after editing** (bind mount requires container recreation):
```bash
./monitoringctl up -d --force-recreate prometheus
```

**View loaded rules:**
```bash
docker exec prometheus wget -qO- 'http://localhost:9090/api/v1/rules' | jq
```

**Check rule syntax before applying:**
```bash
docker run --rm -v $(pwd)/prometheus:/etc/prometheus prom/prometheus promtool check rules /etc/prometheus/alert-rules.yml
```

**View active alerts:**
```bash
docker exec prometheus wget -qO- 'http://localhost:9090/api/v1/alerts' | jq
```

### Testing Alerts

To test the full alert pipeline, temporarily lower a threshold:
```yaml
# In alert-rules.yml, change threshold to trigger immediately
expr: ... > 1  # Instead of > 90
```
Reload rules, wait for the `for` duration (5m), then check Alertmanager and your email. Remember to revert the threshold.

## Architecture

```
grafana.example.com → Traefik → Authelia → Grafana
                                               ↓
                              ┌────────────────┼────────────────┐
                              │                │                │
                         Prometheus          Loki          Alertmanager
                              │                │                │
                    ┌─────────┼─────────┐     Promtail         SES
                    │         │         │         │
               node-exp   cAdvisor   (other)      │
               │    │         │                   │
             local  vps    containers        logs (docker, syslog)
                 (tailscale)
```
