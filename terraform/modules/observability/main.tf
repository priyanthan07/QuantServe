# ---------- Prometheus + Grafana VM ----------

resource "google_compute_instance" "prometheus" {
  name         = "quantserve-prometheus-${var.environment}"
  project      = var.project_id
  zone         = var.zone
  machine_type = "e2-standard-2"

  tags = ["prometheus"]

  boot_disk {
    initialize_params {
      image = "projects/cos-cloud/global/images/family/cos-stable"
      size  = 50
      type  = "pd-ssd"
    }
  }

  network_interface {
    subnetwork = var.subnet_self_link
  }

  service_account {
    email  = var.observability_sa_email
    scopes = ["cloud-platform"]
  }

  metadata = {
    startup-script = replace(<<-SCRIPT
      #!/bin/bash
      set -e

      mkdir -p /home/prometheus/config /home/prometheus/data \
               /home/grafana/data \
               /home/grafana/provisioning/datasources \
               /home/grafana/provisioning/dashboards \
               /home/grafana/dashboards

      chmod -R 777 /home/prometheus /home/grafana

      # ---------- Prometheus config ----------
      cat > /home/prometheus/config/prometheus.yml << 'PROMEOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "/etc/prometheus/alert_rules.yml"

scrape_configs:
  - job_name: 'vllm'
    gce_sd_configs:
      - project: ${var.project_id}
        zone: ${var.zone}
        port: 8000
        filter: '(tags.items = "vllm-serving")'
        refresh_interval: 30s
    relabel_configs:
      - source_labels: [__meta_gce_instance_name]
        target_label: instance_name
      - source_labels: [__meta_gce_metadata_model_id]
        target_label: model_id
    metrics_path: "/metrics"

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
PROMEOF

      # ---------- Alert rules ----------
      cat > /home/prometheus/config/alert_rules.yml << 'ALERTEOF'
groups:
  - name: quantserve_vllm_alerts
    rules:
      - alert: HighGPUCacheUsage
        expr: vllm:gpu_cache_usage_perc > 0.9
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "GPU cache > 90% on {{ $labels.instance_name }}"
      - alert: HighQueueDepth
        expr: vllm:num_requests_waiting > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Queue depth > 5 on {{ $labels.instance_name }}"
      - alert: HighTTFT
        expr: histogram_quantile(0.99, rate(vllm:time_to_first_token_seconds_bucket[5m])) > ${var.ttft_p99_slo_seconds}
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "TTFT p99 above SLO on {{ $labels.instance_name }}"
      - alert: VLLMInstanceDown
        expr: up{job="vllm"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "vLLM instance {{ $labels.instance_name }} is down"
      - alert: ZeroThroughput
        expr: rate(vllm:generation_tokens_total[5m]) == 0 and vllm:num_requests_running > 0
        for: 3m
        labels:
          severity: critical
        annotations:
          summary: "Zero throughput with active requests on {{ $labels.instance_name }}"
ALERTEOF

      # ---------- Grafana datasource ----------
      cat > /home/grafana/provisioning/datasources/prometheus.yml << 'DSEOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: false
DSEOF

      # ---------- Grafana dashboard provider ----------
      cat > /home/grafana/provisioning/dashboards/quantserve.yml << 'DBEOF'
apiVersion: 1
providers:
  - name: QuantServe
    type: file
    options:
      path: /var/lib/grafana/dashboards
DBEOF

      # ---------- vLLM dashboard ----------
      cat > /home/grafana/dashboards/vllm_overview.json << 'DASHEOF'
{
    "dashboard": {
        "title": "QuantServe — vLLM Overview",
        "tags": ["quantserve", "vllm"],
        "timezone": "browser",
        "refresh": "15s",
        "panels": [
            {
                "title": "Requests Running (per model)",
                "type": "timeseries",
                "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
                "targets": [{"expr": "vllm:num_requests_running", "legendFormat": "{{ model_id }} — {{ instance_name }}"}]
            },
            {
                "title": "Requests Waiting (per model)",
                "type": "timeseries",
                "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
                "targets": [{"expr": "vllm:num_requests_waiting", "legendFormat": "{{ model_id }} — {{ instance_name }}"}]
            },
            {
                "title": "TTFT p50 / p95 / p99 (seconds)",
                "type": "timeseries",
                "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
                "targets": [
                    {"expr": "histogram_quantile(0.50, rate(vllm:time_to_first_token_seconds_bucket[5m]))", "legendFormat": "p50 — {{ model_id }}"},
                    {"expr": "histogram_quantile(0.95, rate(vllm:time_to_first_token_seconds_bucket[5m]))", "legendFormat": "p95 — {{ model_id }}"},
                    {"expr": "histogram_quantile(0.99, rate(vllm:time_to_first_token_seconds_bucket[5m]))", "legendFormat": "p99 — {{ model_id }}"}
                ]
            },
            {
                "title": "Inter-Token Latency p95 (seconds)",
                "type": "timeseries",
                "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
                "targets": [{"expr": "histogram_quantile(0.95, rate(vllm:inter_token_latency_seconds_bucket[5m]))", "legendFormat": "{{ model_id }} — {{ instance_name }}"}]
            },
            {
                "title": "GPU KV Cache Usage (%)",
                "type": "gauge",
                "gridPos": {"h": 8, "w": 8, "x": 0, "y": 16},
                "targets": [{"expr": "vllm:gpu_cache_usage_perc", "legendFormat": "{{ model_id }} — {{ instance_name }}"}],
                "fieldConfig": {"defaults": {"min": 0, "max": 1, "thresholds": {"steps": [{"color": "green", "value": 0}, {"color": "yellow", "value": 0.7}, {"color": "red", "value": 0.9}]}}}
            },
            {
                "title": "Prefix Cache Hit Rate",
                "type": "timeseries",
                "gridPos": {"h": 8, "w": 8, "x": 8, "y": 16},
                "targets": [{"expr": "rate(vllm:prefix_cache_hit_total[5m]) / (rate(vllm:prefix_cache_hit_total[5m]) + rate(vllm:prefix_cache_miss_total[5m]))", "legendFormat": "{{ model_id }}"}]
            },
            {
                "title": "Token Throughput (tokens/sec)",
                "type": "timeseries",
                "gridPos": {"h": 8, "w": 8, "x": 16, "y": 16},
                "targets": [{"expr": "rate(vllm:generation_tokens_total[1m])", "legendFormat": "{{ model_id }} — {{ instance_name }}"}]
            }
        ]
    }
}
DASHEOF

      # ---------- Wait for Docker Hub to be reachable ----------
      for i in $(seq 1 10); do
        if docker pull prom/prometheus:v2.54.1; then
          break
        fi
        echo "[quantserve] Docker Hub not reachable yet, retrying in 5s... ($i/10)"
        sleep 5
      done

      # ---------- Start Prometheus ----------
      docker run -d \
        --name prometheus \
        --restart always \
        -p 9090:9090 \
        -v /home/prometheus/config:/etc/prometheus \
        -v /home/prometheus/data:/prometheus \
        prom/prometheus:v2.54.1 \
        --config.file=/etc/prometheus/prometheus.yml \
        --storage.tsdb.retention.time=30d

      # ---------- Start Grafana ----------
      GRAFANA_ADMIN_PASSWORD=$(docker run --rm --network=host google/cloud-sdk:slim \
        gcloud secrets versions access latest \
        --secret="${var.grafana_admin_password_secret_id}" \
        --project="${var.project_id}")

      docker run -d \
        --name grafana \
        --restart always \
        -p 3000:3000 \
        -v /home/grafana/data:/var/lib/grafana \
        -v /home/grafana/provisioning:/etc/grafana/provisioning \
        -v /home/grafana/dashboards:/var/lib/grafana/dashboards \
        -e "GF_SECURITY_ADMIN_PASSWORD=$${GRAFANA_ADMIN_PASSWORD}" \
        -e "GF_SERVER_SERVE_FROM_SUB_PATH=true" \
        -e "GF_SERVER_ROOT_URL=https://${var.domain_suffix}/grafana/" \
        grafana/grafana:11.2.0
    SCRIPT
    , "\r\n", "\n")
  }
}

# ---------- Instance group for the shared LB ----------

resource "google_compute_instance_group" "grafana" {
  name        = "quantserve-grafana-${var.environment}"
  project     = var.project_id
  zone        = var.zone
  description = "Instance group wrapping the Prometheus/Grafana VM"

  instances = [google_compute_instance.prometheus.self_link]

  named_port {
    name = "grafana"
    port = 3000
  }
}

# ---------- Health check for Grafana ----------

resource "google_compute_health_check" "grafana" {
  name    = "quantserve-grafana-health-${var.environment}"
  project = var.project_id

  check_interval_sec  = 15
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = 3000
    request_path = "/grafana/api/health"
  }
}

# ---------- Cloud Monitoring alert policies ----------

resource "google_monitoring_notification_channel" "email" {
  count        = var.alert_notification_channel_email != "" ? 1 : 0
  project      = var.project_id
  display_name = "QuantServe Alerts"
  type         = "email"

  labels = {
    email_address = var.alert_notification_channel_email
  }
}

resource "google_monitoring_alert_policy" "vllm_instance_down" {
  project      = var.project_id
  display_name = "QuantServe: vLLM instance down"
  combiner     = "OR"

  conditions {
    display_name = "vLLM instance not responding"
    condition_prometheus_query_language {
      query    = "up{job=\"vllm\"} == 0"
      duration = "60s"
    }
  }

  notification_channels = var.alert_notification_channel_email != "" ? [
    google_monitoring_notification_channel.email[0].name
  ] : []
}
