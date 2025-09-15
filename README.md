# Self‑Hosted Analytics Stack

**Components:** Umami (visitors) · OpenReplay (session replay) · Loki/Promtail (logs) · Prometheus (metrics) · Grafana (dashboards) · Uptime Kuma (uptime)

> This doc gives you a ready‑to‑run Docker setup plus minimal configs. Replace all `CHANGE_ME_*` secrets. You can run everything on one box; OpenReplay is heavier and is split into its own compose file.

---

## Automated Deployment

This project includes an automated deployment script that simplifies the setup process and makes it completely portable. To get started, make sure you have Docker and Docker Compose installed on your system, and then run the following command:

```bash
bash deploy.sh
```

The script will guide you through the configuration process and automatically adapt to your setup:

### Three deployment options:

1. **Domain names with SSL** (Traditional setup):

   - Provides HTTPS with automatic SSL certificates via Caddy
   - Clean, professional URLs
   - Requires domain names pointing to your server

2. **IP addresses** (Direct access):

   - Works immediately without domain setup
   - Uses HTTP (no SSL) for simplicity
   - Automatically detects your server's public IP
   - Perfect for quick testing or development

3. **Cloudflare Tunnels** (Recommended for VPS):
   - Most secure and portable option
   - No need to expose ports or configure SSL
   - Works behind firewalls and NAT
   - Uses localhost internally, Cloudflare handles external access
   - Perfect for VPS deployments

### What the script does:

- **Dependency Checks**: Verifies that Docker and Docker-Compose are installed
- **Flexible Configuration**: Adapts to your chosen access method
- **Automatic IP Detection**: If using IPs, detects your server's public IP
- **Secret Generation**: Automatically creates secure passwords for all services
- **Smart Proxy Setup**: Configures Caddy for domains/IPs or skips it for Cloudflare Tunnels
- **Service Deployment**: Starts the core analytics stack and optionally OpenReplay

The setup is completely portable - you can move it to any VPS and it will automatically adapt to the new environment.

### Cloudflare Tunnels Setup

If you choose option 3, you'll need to configure your Cloudflare Tunnel. See `cloudflare-tunnel-example.yml` for a configuration template.

For more details on the manual setup process, you can refer to the sections below.

---

## Folder layout

```
analytics-stack/
├─ .env
├─ docker-compose.yml                # Umami + Postgres, Loki, Promtail, Grafana, Prometheus, cAdvisor, node-exporter, Uptime Kuma
├─ prometheus/
│  └─ prometheus.yml
├─ loki/
│  └─ loki-config.yml
├─ promtail/
│  └─ promtail-config.yml
└─ openreplay/
   └─ docker-compose.openreplay.yml  # Optional: run separately due to weight
```

---

## .env (template)

```env
# Global
TZ=America/Los_Angeles

# Grafana
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=CHANGE_ME_GRAFANA

# Umami
UMAMI_APP_SECRET=CHANGE_ME_UMAMI
UMAMI_DB_USER=umami
UMAMI_DB_PASS=CHANGE_ME_UMAMI_DB

# Postgres (Umami)
POSTGRES_DB=umami
POSTGRES_USER=${UMAMI_DB_USER}
POSTGRES_PASSWORD=${UMAMI_DB_PASS}

# Uptime Kuma
UPTIME_KUMA_PORT=3001

# Loki
LOKI_RETENTION_PERIOD=168h   # 7 days (tune up)
```

---

## docker-compose.yml (core stack)

```yaml
version: "3.9"

services:
  # --- Visitor analytics ---
  postgres:
    image: postgres:16
    container_name: pg-umami
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      TZ: ${TZ}
    volumes:
      - pgdata:/var/lib/postgresql/data
    restart: unless-stopped

  umami:
    image: ghcr.io/umami-software/umami:postgresql-latest
    container_name: umami
    depends_on: [postgres]
    environment:
      DATABASE_URL: postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      APP_SECRET: ${UMAMI_APP_SECRET}
      TRACKER_SCRIPT_NAME: script.js
      TZ: ${TZ}
    ports:
      - "8081:3000" # http://YOUR_SERVER:8081
    restart: unless-stopped

  # --- Logs (Loki + Promtail) ---
  loki:
    image: grafana/loki:2.9.8
    container_name: loki
    command: ["-config.file=/etc/loki/loki-config.yml"]
    volumes:
      - ./loki/loki-config.yml:/etc/loki/loki-config.yml:ro
      - loki-data:/loki
    ports:
      - "3100:3100"
    restart: unless-stopped

  promtail:
    image: grafana/promtail:2.9.8
    container_name: promtail
    command: ["-config.file=/etc/promtail/promtail-config.yml"]
    volumes:
      - ./promtail/promtail-config.yml:/etc/promtail/promtail-config.yml:ro
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    depends_on: [loki]
    restart: unless-stopped

  # --- Metrics (Prometheus + exporters) ---
  prometheus:
    image: prom/prometheus:v2.55.1
    container_name: prometheus
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prom-data:/prometheus
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --web.enable-lifecycle
    ports:
      - "9090:9090"
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:v1.8.1
    container_name: node-exporter
    pid: host
    network_mode: host
    command: ["--path.rootfs=/host"]
    volumes:
      - /:/host:ro,rslave
    restart: unless-stopped

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.49.1
    container_name: cadvisor
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    restart: unless-stopped

  # --- Dashboards ---
  grafana:
    image: grafana/grafana:11.1.0
    container_name: grafana
    environment:
      GF_SECURITY_ADMIN_USER: ${GF_SECURITY_ADMIN_USER}
      GF_SECURITY_ADMIN_PASSWORD: ${GF_SECURITY_ADMIN_PASSWORD}
      TZ: ${TZ}
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana
    depends_on: [prometheus, loki]
    restart: unless-stopped

  # --- Uptime ---
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    ports:
      - "${UPTIME_KUMA_PORT}:3001" # http://YOUR_SERVER:${UPTIME_KUMA_PORT}
    volumes:
      - kuma-data:/app/data
    restart: unless-stopped

volumes:
  pgdata:
  prom-data:
  grafana-data:
  loki-data:
  kuma-data:
```

---

## loki/loki-config.yml (minimal)

```yaml
auth_enabled: false
server:
  http_listen_port: 3100
common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory
query_range:
  parallelise_shardable_queries: true
limits_config:
  retention_period: ${LOKI_RETENTION_PERIOD}
schema_config:
  configs:
    - from: 2024-01-01
      store: boltdb-shipper
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h
ruler:
  alertmanager_url: http://localhost:9093
```

---

## promtail/promtail-config.yml (Docker logs)

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0
positions:
  filename: /tmp/positions.yaml
clients:
  - url: http://loki:3100/loki/api/v1/push
scrape_configs:
  - job_name: docker-logs
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 10s
    relabel_configs:
      - source_labels: ["__meta_docker_container_name"]
        regex: "/(.*)"
        target_label: container
    pipeline_stages:
      - docker: {}
```

---

## prometheus/prometheus.yml (basic scrapes)

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["prometheus:9090"]

  - job_name: "node-exporter"
    static_configs:
      - targets: ["localhost:9100"]

  - job_name: "cadvisor"
    static_configs:
      - targets: ["cadvisor:8080"]
```

> Add more scrape targets (your apps) later; expose Prometheus metrics at `/metrics` per service or via exporters.

---

## OpenReplay (self‑host, minimal single‑node)

> OpenReplay is heavier. Run it **separately** (inside `openreplay/docker-compose.openreplay.yml`). Tune resources and storage paths.

```yaml
version: "3.9"
services:
  # Core deps
  zookeeper:
    image: bitnami/zookeeper:3.9
    environment: [ALLOW_ANONYMOUS_LOGIN=yes]
    restart: unless-stopped
  kafka:
    image: bitnami/kafka:3.7
    environment:
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_LISTENERS=PLAINTEXT://:9092
      - KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092
    depends_on: [zookeeper]
    restart: unless-stopped
  redis:
    image: redis:7
    restart: unless-stopped
  postgres:
    image: postgres:16
    environment: POSTGRES_DB=openreplay
      POSTGRES_USER=openreplay
      POSTGRES_PASSWORD=CHANGE_ME_OR
    volumes: [or-pg:/var/lib/postgresql/data]
    restart: unless-stopped
  clickhouse:
    image: clickhouse/clickhouse-server:23.12
    ulimits:
      nofile: { soft: 262144, hard: 262144 }
    volumes: [or-ch:/var/lib/clickhouse]
    restart: unless-stopped
  minio:
    image: bitnami/minio:2024
    environment:
      MINIO_ROOT_USER: admin
      MINIO_ROOT_PASSWORD: CHANGE_ME_MINIO
    command: ["server", "/data", "--console-address", "0.0.0.0:9001"]
    volumes: [or-minio:/data]
    ports: ["9000:9000", "9001:9001"]
    restart: unless-stopped

  # OpenReplay services (simplified)
  ingester:
    image: openreplay/ingest:latest
    environment:
      KAFKA_BROKERS: kafka:9092
      CLICKHOUSE_ADDR: clickhouse:8123
      REDIS_URL: redis://redis:6379
      S3_ENDPOINT: http://minio:9000
      S3_BUCKET_SESSIONS: sessions
      S3_ACCESS_KEY: admin
      S3_SECRET_KEY: CHANGE_ME_MINIO
      S3_FORCE_PATH_STYLE: "true"
    depends_on: [kafka, clickhouse, redis, minio]
    restart: unless-stopped
  api:
    image: openreplay/api:latest
    environment:
      DATABASE_URL: postgres://openreplay:CHANGE_ME_OR@postgres:5432/openreplay
      CLICKHOUSE_ADDR: clickhouse:8123
      REDIS_URL: redis://redis:6379
      S3_ENDPOINT: http://minio:9000
      S3_BUCKET_SESSIONS: sessions
      S3_ACCESS_KEY: admin
      S3_SECRET_KEY: CHANGE_ME_MINIO
      S3_FORCE_PATH_STYLE: "true"
    depends_on: [postgres, clickhouse, redis, minio]
    restart: unless-stopped
  web:
    image: openreplay/web:latest
    environment:
      API_URL: http://api:8080
    ports: ["8082:80"]
    depends_on: [api]
    restart: unless-stopped

volumes:
  or-pg:
  or-ch:
  or-minio:
```

> After the stack is up, create an OpenReplay project in the web UI (http\://YOUR_SERVER:8082), grab the project key, and inject the snippet into your app.

---

## Next.js integration (quick snippets)

**Umami** – in `<head>` of your app shell:

```html
<script
  async
  src="https://YOUR_DOMAIN_OR_IP:8081/script.js"
  data-website-id="YOUR-UMAMI-ID"
></script>
```

**Web Vitals → logs/metrics** – add `reportWebVitals` and POST to your own collector:

```ts
// reportWebVitals.ts
import type { ReportHandler } from "web-vitals";
export const reportWebVitals: ReportHandler = (metric) => {
  navigator.sendBeacon?.("/api/vitals", JSON.stringify(metric)) ||
    fetch("/api/vitals", {
      method: "POST",
      keepalive: true,
      body: JSON.stringify(metric),
    });
};
```

**OpenReplay snippet** – from your OpenReplay project UI, paste the script into your app (only on production pages). Use CSP nonces if you have CSP.

---

## Run

```bash
# Core stack
docker compose up -d

# OpenReplay (in its folder)
cd openreplay && docker compose -f docker-compose.openreplay.yml up -d
```

---

## Hardening & tips

- Put Nginx/Caddy in front with TLS; protect Grafana/Umami/OpenReplay with auth.
- Enforce data retention (Loki `retention_period`, Prometheus `--storage.tsdb.retention.time`).
- Back up Postgres (Umami, OpenReplay) and ClickHouse regularly.
- Label everything (`app`, `env`, `service`) for clean Grafana/Loki queries.
- For Atlas MongoDB, restrict to your static IP in **Network Access**; self‑hosted Mongo: bind to private IP + firewall + auth + TLS.

---

## Grafana — full auto‑provisioning

Place these files under `grafana/` and (re)start Grafana. They will auto‑create **data sources, folders, dashboards, and alerts**.

### Folder layout

```
analytics-stack/
└─ grafana/
   ├─ provisioning/
   │  ├─ datasources/
   │  │  └─ datasources.yml
   │  ├─ dashboards/
   │  │  └─ dashboards.yml
   │  └─ alerting/
   │     └─ provisioning.yml
   └─ dashboards/
      ├─ 00_system_overview.json
      ├─ 10_web_vitals.json
      ├─ 20_traffic_analytics.json
      ├─ 30_errors_logs.json
      └─ 40_uptime.json
```

### `provisioning/datasources/datasources.yml`

```yaml
apiVersion: 1

# Prometheus (metrics)
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true

  # Loki (logs)
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100

  # Umami Postgres (visitor analytics)
  - name: Umami-Postgres
    type: postgres
    access: proxy
    url: postgres:5432
    user: ${POSTGRES_USER}
    secureJsonData:
      password: ${POSTGRES_PASSWORD}
    jsonData:
      database: ${POSTGRES_DB}
      sslmode: disable
      postgresVersion: 1600

  # OpenReplay ClickHouse (sessions)
  - name: OpenReplay-ClickHouse
    type: grafana-clickhouse-datasource
    access: proxy
    url: http://clickhouse:8123
    jsonData:
      defaultDatabase: default
      xAxisMode: time
      httpMethod: POST

  # Uptime Kuma (metrics via Prometheus endpoint)
  - name: Kuma-Prom
    type: prometheus
    access: proxy
    url: http://uptime-kuma:3001/metrics
    editable: true
```

> Note: for ClickHouse, install the Grafana plugin `grafana-clickhouse-datasource`. With Docker: add env `GF_INSTALL_PLUGINS=grafana-clickhouse-datasource` to the Grafana service in your compose.

### `provisioning/dashboards/dashboards.yml`

```yaml
apiVersion: 1
providers:
  - name: Default Dashboards
    orgId: 1
    folder: ""
    type: file
    disableDeletion: false
    allowUiUpdates: true
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
```

### Example dashboards (minimal, editable)

You can start with these small JSONs and expand later.

#### `dashboards/00_system_overview.json`

```json
{
  "id": null,
  "title": "System Overview",
  "timezone": "browser",
  "schemaVersion": 39,
  "version": 1,
  "panels": [
    {
      "type": "stat",
      "title": "CPU %",
      "gridPos": { "x": 0, "y": 0, "w": 6, "h": 4 },
      "targets": [
        {
          "datasource": { "type": "prometheus", "uid": "Prometheus" },
          "expr": "100 - (avg by(instance)(rate(node_cpu_seconds_total{mode=\"idle\"}[5m]))*100)"
        }
      ]
    },

    {
      "type": "stat",
      "title": "Memory Used %",
      "gridPos": { "x": 6, "y": 0, "w": 6, "h": 4 },
      "targets": [
        {
          "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100"
        }
      ]
    },

    {
      "type": "timeseries",
      "title": "Container CPU",
      "gridPos": { "x": 0, "y": 4, "w": 12, "h": 8 },
      "targets": [
        {
          "expr": "sum by (container_label_com_docker_compose_service)(rate(container_cpu_usage_seconds_total[5m]))"
        }
      ]
    }
  ]
}
```

#### `dashboards/10_web_vitals.json`

```json
{
  "title": "Web Vitals",
  "schemaVersion": 39,
  "panels": [
    {
      "type": "timeseries",
      "title": "LCP p75",
      "gridPos": { "x": 0, "y": 0, "w": 12, "h": 8 },
      "targets": [
        {
          "datasource": { "type": "prometheus", "uid": "Prometheus" },
          "expr": "histogram_quantile(0.75, sum by(le,route)(rate(web_vitals_lcp_seconds_bucket[5m])))"
        }
      ]
    },
    {
      "type": "timeseries",
      "title": "CLS avg",
      "gridPos": { "x": 0, "y": 8, "w": 12, "h": 8 },
      "targets": [
        {
          "expr": "avg by(route)(rate(web_vitals_cls_score_sum[5m]) / rate(web_vitals_cls_score_count[5m]))"
        }
      ]
    }
  ]
}
```

#### `dashboards/20_traffic_analytics.json`

```json
{
  "title": "Traffic Analytics (Umami)",
  "schemaVersion": 39,
  "panels": [
    {
      "type": "table",
      "title": "Top Pages",
      "gridPos": { "x": 0, "y": 0, "w": 12, "h": 8 },
      "targets": [
        {
          "datasource": { "type": "postgres", "uid": "Umami-Postgres" },
          "format": "table",
          "rawSql": "SELECT url, SUM(count) AS views FROM pageviews WHERE created_at > now() - interval '7 days' GROUP BY 1 ORDER BY 2 DESC LIMIT 50;"
        }
      ]
    },
    {
      "type": "piechart",
      "title": "Traffic by Country",
      "gridPos": { "x": 0, "y": 8, "w": 12, "h": 8 },
      "targets": [
        {
          "datasource": { "type": "postgres", "uid": "Umami-Postgres" },
          "format": "table",
          "rawSql": "SELECT country, SUM(count) AS views FROM sessions WHERE created_at > now() - interval '7 days' GROUP BY 1 ORDER BY 2 DESC LIMIT 20;"
        }
      ]
    }
  ]
}
```

#### `dashboards/30_errors_logs.json`

```json
{
  "title": "Errors & Logs",
  "schemaVersion": 39,
  "panels": [
    {
      "type": "logs",
      "title": "App Logs (Loki)",
      "gridPos": { "x": 0, "y": 0, "w": 12, "h": 10 },
      "targets": [
        {
          "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "{app=\"nextjs\"}"
        }
      ]
    },
    {
      "type": "timeseries",
      "title": "5xx rate",
      "gridPos": { "x": 0, "y": 10, "w": 12, "h": 6 },
      "targets": [
        {
          "datasource": { "type": "loki", "uid": "Loki" },
          "expr": "sum(rate({app=\"nginx\"} |= \" 5\" [5m]))"
        }
      ]
    }
  ]
}
```

#### `dashboards/40_uptime.json`

```json
{
  "title": "Uptime",
  "schemaVersion": 39,
  "panels": [
    {
      "type": "stat",
      "title": "Availability % (24h)",
      "gridPos": { "x": 0, "y": 0, "w": 6, "h": 4 },
      "targets": [
        {
          "datasource": { "type": "prometheus", "uid": "Kuma-Prom" },
          "expr": "avg( probe_success ) * 100"
        }
      ]
    },
    {
      "type": "timeseries",
      "title": "Response Time",
      "gridPos": { "x": 0, "y": 4, "w": 12, "h": 8 },
      "targets": [
        {
          "datasource": { "type": "prometheus", "uid": "Kuma-Prom" },
          "expr": "avg_over_time(probe_duration_seconds[5m])"
        }
      ]
    }
  ]
}
```

### `provisioning/alerting/provisioning.yml` (contact points + a sample rule)

```yaml
apiVersion: 1
contactPoints:
  - orgId: 1
    name: oncall
    receivers:
      - uid: slack
        type: slack
        settings:
          url: ${SLACK_WEBHOOK_URL}
          title: "Grafana Alert"
          text: "{{ .CommonAnnotations.summary }}"

notificationPolicies:
  - orgId: 1
    receiver: oncall
    group_by: [alertname]

policies:
  - orgId: 1
    receiver: oncall

# Rule group example (Web Vitals LCP p75 > 4s for 5m)
groups:
  - orgId: 1
    name: UX Rules
    folder: "General"
    interval: 1m
    rules:
      - uid: lcp-high
        title: "LCP p75 too high"
        condition: C
        data:
          - refId: A
            relativeTimeRange:
              from: 300
              to: 0
            datasourceUid: Prometheus
            model:
              expr: histogram_quantile(0.75, sum by(le)(rate(web_vitals_lcp_seconds_bucket[5m])))
              intervalMs: 60000
              maxDataPoints: 43200
          - refId: B
            relativeTimeRange:
              from: 300
              to: 0
            datasourceUid: Prometheus
            model:
              expr: 4
              intervalMs: 60000
              maxDataPoints: 43200
        noDataState: NoData
        execErrState: Error
        for: 5m
        annotations:
          summary: "LCP p75 above 4s"
        labels:
          severity: warning
```

### Enable the ClickHouse plugin

Add to your Grafana service (compose):

```
GF_INSTALL_PLUGINS=grafana-clickhouse-datasource
```

### Restart to apply

```bash
docker compose restart grafana
```

**Done.** Grafana will auto‑load data sources, dashboards, and alerting. Edit the SQL/PromQL/Loki queries to fit your schemas & labels.

---

## Grafana — full auto‑provisioning

Place these files under `grafana/` and (re)start Grafana. They will auto‑create **data sources, folders, dashboards, and alerts**.

### Folder layout

```
analytics-stack/
└─ grafana/
   ├─ provisioning/
   │  ├─ datasources/
   │  │  └─ datasources.yml
   │  ├─ dashboards/
   │  │  └─ dashboards.yml
   │  └─ alerting/
   │     └─ provisioning.yml
   └─ dashboards/
      ├─ 00_system_overview.json
      ├─ 10_web_vitals.json
      ├─ 20_traffic_analytics.json
      ├─ 30_errors_logs.json
      └─ 40_uptime.json
```

### `provisioning/datasources/datasources.yml`

```yaml
apiVersion: 1

# Prometheus (metrics)
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true

  # Loki (logs)
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100

  # Umami Postgres (visitor analytics)
  - name: Umami-Postgres
    type: postgres
    access: proxy
    url: postgres:5432
    user: ${POSTGRES_USER}
    secureJsonData:
      password: ${POSTGRES_PASSWORD}
    jsonData:
      database: ${POSTGRES_DB}
      sslmode: disable
      postgresVersion: 1600

  # OpenReplay ClickHouse (sessions)
  - name: OpenReplay-ClickHouse
    type: grafana-clickhouse-datasource
    access: proxy
    url: http://clickhouse:8123
    jsonData:
      defaultDatabase: default
      xAxisMode: time
      httpMethod: POST

  # Uptime Kuma (metrics via Prometheus endpoint)
  - name: Kuma-Prom
    type: prometheus
    access: proxy
    url: http://uptime-kuma:3001/metrics
    editable: true
```

> Note: for ClickHouse, install the Grafana plugin `grafana-clickhouse-datasource`. With Docker: add env `GF_INSTALL_PLUGINS=grafana-clickhouse-datasource` to the Grafana service in your compose.

### `provisioning/dashboards/dashboards.yml`

```yaml
apiVersion: 1
providers:
  - name: Default Dashboards
    orgId: 1
    folder: ""
    type: file
    disableDeletion: false
    allowUiUpdates: true
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
```

### Example dashboards (minimal, editable)

You can start with these small JSONs and expand later.

#### `dashboards/00_system_overview.json`

```json
{
  "id": null,
  "title": "System Overview",
  "timezone": "browser",
  "schemaVersion": 39,
  "version": 1,
  "panels": [
    {
      "type": "stat",
      "title": "CPU %",
      "gridPos": { "x": 0, "y": 0, "w": 6, "h": 4 },
      "targets": [
        {
          "datasource": { "type": "prometheus", "uid": "Prometheus" },
          "expr": "100 - (avg by(instance)(rate(node_cpu_seconds_total{mode=\"idle\"}[5m]))*100)"
        }
      ]
    },

    {
      "type": "stat",
      "title": "Memory Used %",
      "gridPos": { "x": 6, "y": 0, "w": 6, "h": 4 },
      "targets": [
        {
          "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100"
        }
      ]
    },

    {
      "type": "timeseries",
      "title": "Container CPU",
      "gridPos": { "x": 0, "y": 4, "w": 12, "h": 8 },
      "targets": [
        {
          "expr": "sum by (container_label_com_docker_compose_service)(rate(container_cpu_usage_seconds_total[5m]))"
        }
      ]
    }
  ]
}
```

#### `dashboards/10_web_vitals.json`

```json
{
  "title": "Web Vitals",
  "schemaVersion": 39,
  "panels": [
    {
      "type": "timeseries",
      "title": "LCP p75",
      "gridPos": { "x": 0, "y": 0, "w": 12, "h": 8 },
      "targets": [
        {
          "datasource": { "type": "prometheus", "uid": "Prometheus" },
          "expr": "histogram_quantile(0.75, sum by(le,route)(rate(web_vitals_lcp_seconds_bucket[5m])))"
        }
      ]
    },
    {
      "type": "timeseries",
      "title": "CLS avg",
      "gridPos": { "x": 0, "y": 8, "w": 12, "h": 8 },
      "targets": [
        {
          "expr": "avg by(route)(rate(web_vitals_cls_score_sum[5m]) / rate(web_vitals_cls_score_count[5m]))"
        }
      ]
    }
  ]
}
```

#### `dashboards/20_traffic_analytics.json`

```json
{
  "title": "Traffic Analytics (Umami)",
  "schemaVersion": 39,
  "panels": [
    {
      "type": "table",
      "title": "Top Pages",
      "gridPos": { "x": 0, "y": 0, "w": 12, "h": 8 },
      "targets": [
        {
          "datasource": { "type": "postgres", "uid": "Umami-Postgres" },
          "format": "table",
          "rawSql": "SELECT url, SUM(count) AS views FROM pageviews WHERE created_at > now() - interval '7 days' GROUP BY 1 ORDER BY 2 DESC LIMIT 50;"
        }
      ]
    },
    {
      "type": "piechart",
      "title": "Traffic by Country",
      "gridPos": { "x": 0, "y": 8, "w": 12, "h": 8 },
      "targets": [
        {
          "datasource": { "type": "postgres", "uid": "Umami-Postgres" },
          "format": "table",
          "rawSql": "SELECT country, SUM(count) AS views FROM sessions WHERE created_at > now() - interval '7 days' GROUP BY 1 ORDER BY 2 DESC LIMIT 20;"
        }
      ]
    }
  ]
}
```

#### `dashboards/30_errors_logs.json`

```json
{
  "title": "Errors & Logs",
  "schemaVersion": 39,
  "panels": [
    {"type":"logs","title":"App Logs (Loki)","gridPos":{"x":0,"y":0,"w":12,"h":10},
     "targets":[{"datasource":{"type":"loki","uid":"Loki"},
       "expr":"{app=\"nextjs\"}"}]},
    {"type":"timeseries","title":"5xx rate","gridPos":{"x":0,"y":10,"w":12,"h":6},
     "targets":[{"datasource":{"type":"loki","uid":"Loki"},
       "expr":"sum(rate({app=\"nginx\"} |= \" 5\\" [5m]))"}]}
  ]
}
```

#### `dashboards/40_uptime.json`

```json
{
  "title": "Uptime",
  "schemaVersion": 39,
  "panels": [
    {
      "type": "stat",
      "title": "Availability % (24h)",
      "gridPos": { "x": 0, "y": 0, "w": 6, "h": 4 },
      "targets": [
        {
          "datasource": { "type": "prometheus", "uid": "Kuma-Prom" },
          "expr": "avg( probe_success ) * 100"
        }
      ]
    },
    {
      "type": "timeseries",
      "title": "Response Time",
      "gridPos": { "x": 0, "y": 4, "w": 12, "h": 8 },
      "targets": [
        {
          "datasource": { "type": "prometheus", "uid": "Kuma-Prom" },
          "expr": "avg_over_time(probe_duration_seconds[5m])"
        }
      ]
    }
  ]
}
```

### `provisioning/alerting/provisioning.yml` (contact points + a sample rule)

```yaml
apiVersion: 1
contactPoints:
  - orgId: 1
    name: oncall
    receivers:
      - uid: slack
        type: slack
        settings:
          url: ${SLACK_WEBHOOK_URL}
          title: "Grafana Alert"
          text: "{{ .CommonAnnotations.summary }}"

notificationPolicies:
  - orgId: 1
    receiver: oncall
    group_by: [alertname]

policies:
  - orgId: 1
    receiver: oncall

# Rule group example (Web Vitals LCP p75 > 4s for 5m)
groups:
  - orgId: 1
    name: UX Rules
    folder: "General"
    interval: 1m
    rules:
      - uid: lcp-high
        title: "LCP p75 too high"
        condition: C
        data:
          - refId: A
            relativeTimeRange:
              from: 300
              to: 0
            datasourceUid: Prometheus
            model:
              expr: histogram_quantile(0.75, sum by(le)(rate(web_vitals_lcp_seconds_bucket[5m])))
              intervalMs: 60000
              maxDataPoints: 43200
          - refId: B
            relativeTimeRange:
              from: 300
              to: 0
            datasourceUid: Prometheus
            model:
              expr: 4
              intervalMs: 60000
              maxDataPoints: 43200
        noDataState: NoData
        execErrState: Error
        for: 5m
        annotations:
          summary: "LCP p75 above 4s"
        labels:
          severity: warning
```

### Enable the ClickHouse plugin

Add to your Grafana service (compose):

```
GF_INSTALL_PLUGINS=grafana-clickhouse-datasource
```

### Restart to apply

```bash
docker compose restart grafana
```

**Done.** Grafana will auto‑load data sources, dashboards, and alerting. Edit the SQL/PromQL/Loki queries to fit your schemas & labels.
