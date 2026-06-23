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
    # No external IP
  }

  service_account {
    email  = var.observability_sa_email
    scopes = ["cloud-platform"]
  }

  metadata = {
    startup-script = <<-SCRIPT
      #!/bin/bash
      set -e

      # Container-Optimized OS has Docker pre-installed
      # Create data directories
      mkdir -p /home/prometheus/config /home/prometheus/data /home/grafana/data

      # Write Prometheus config
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
            - source_labels: [__meta_gce_instance_name]
              regex: "quantserve-(.+)-[a-z0-9]+"
              target_label: model_id
              replacement: "$1"
          metrics_path: "/metrics"
      PROMEOF

      # Write alert rules (NEW — this block did not exist before)
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

      # Start Prometheus
      docker run -d \
        --name prometheus \
        --restart always \
        -p 9090:9090 \
        -v /home/prometheus/config:/etc/prometheus \
        -v /home/prometheus/data:/prometheus \
        prom/prometheus:2.54.0 \
        --config.file=/etc/prometheus/prometheus.yml \
        --storage.tsdb.retention.time=30d

      # Start Grafana
      docker run -d \
        --name grafana \
        --restart always \
        -p 3000:3000 \
        -v /home/grafana/data:/var/lib/grafana \
        -e "GF_SECURITY_ADMIN_PASSWORD=changeme" \
        grafana/grafana:11.2.0
    SCRIPT
  }
}

# ---------- Alert Policies ----------

resource "google_monitoring_notification_channel" "email" {
  count        = var.alert_notification_channel_email != "" ? 1 : 0
  project      = var.project_id
  display_name = "QuantServe Alerts"
  type         = "email"

  labels = {
    email_address = var.alert_notification_channel_email
  }
}

# Alert: high GPU cache usage (OOM risk)
resource "google_monitoring_alert_policy" "gpu_cache_high" {
  project      = var.project_id
  display_name = "QuantServe: GPU Cache Usage > 90%"
  combiner     = "OR"

  conditions {
    display_name = "GPU cache usage exceeds 90%"
    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/vllm/gpu_cache_usage_perc\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.9
      duration        = "120s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.alert_notification_channel_email != "" ? [
    google_monitoring_notification_channel.email[0].name
  ] : []
}

resource "google_monitoring_alert_policy" "high_ttft" {
  project      = var.project_id
  display_name = "QuantServe: TTFT p99 above SLO"
  combiner     = "OR"

  conditions {
    display_name = "TTFT p99 exceeds ${var.ttft_p99_slo_seconds}s"
    condition_prometheus_query_language {
      query    = "histogram_quantile(0.99, rate(vllm:time_to_first_token_seconds_bucket[5m])) > ${var.ttft_p99_slo_seconds}"
      duration = "300s"
    }
  }

  notification_channels = var.alert_notification_channel_email != "" ? [
    google_monitoring_notification_channel.email[0].name
  ] : []
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
